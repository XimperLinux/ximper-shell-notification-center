namespace XimperShellNotificationCenter.Widgets {

    private struct VpnInfo {
        string name;
        ObjectPath conn_path;
        bool is_active;
        ObjectPath ?active_path;
    }

    public class VpnTile : QuickSettingsTile {
        private NetworkManagerProxy nm_proxy;
        private Gee.ArrayList<VpnInfo?> vpn_list =
            new Gee.ArrayList<VpnInfo?> ();
        private uint sync_timeout = 0;
        private Gtk.Box ?current_submenu = null;
        private bool updating_submenu = false;
        private bool connecting = false;

        ~VpnTile () {
            if (sync_timeout != 0) {
                Source.remove (sync_timeout);
            }
        }

        public VpnTile (Json.Object ?cfg) {
            base ("network-vpn-symbolic", _("VPN"));
            setup_arrow ();
            nm_proxy = NetworkManagerProxy.get_instance ();
            nm_proxy.state_changed.connect (schedule_sync);
        }

        public override bool is_available () {
            return nm_proxy.available;
        }

        public override void on_toggle () {
            toggle_vpn.begin ();
        }

        public override void on_cc_visibility_change (
                bool visible) {
            if (visible) {
                sync_state.begin ();
            } else {
                current_submenu = null;
                connecting = false;
            }
        }

        private void schedule_sync () {
            if (sync_timeout != 0) {
                Source.remove (sync_timeout);
            }
            sync_timeout = Timeout.add (500, () => {
                sync_timeout = 0;
                on_debounced_update.begin ();
                return Source.REMOVE;
            });
        }

        private async void on_debounced_update () {
            bool was_active = active;
            yield sync_state ();

            if (was_active != active) {
                connecting = false;
                refresh_submenu.begin ();
            } else if (!connecting) {
                refresh_submenu.begin ();
            }
        }

        private async void sync_state () {
            yield load_vpn_list ();

            bool any_active = false;
            string ?active_name = null;
            foreach (var vpn in vpn_list) {
                if (vpn.is_active) {
                    any_active = true;
                    active_name = vpn.name;
                    break;
                }
            }

            active = any_active;
            if (any_active && active_name != null) {
                set_subtitle (active_name);
            } else {
                set_subtitle (_("Disconnected"));
            }
        }

        private async void load_vpn_list () {
            var new_list = new Gee.ArrayList<VpnInfo?> ();
            var seen = new Gee.HashSet<string> ();

            // Get active VPN connections
            var active_vpns =
                new Gee.HashMap<string, ObjectPath> ();
            try {
                var nm = nm_proxy.get_nm ();
                if (nm != null) {
                    foreach (var ac_path
                             in nm.active_connections) {
                        try {
                            var ac = yield Bus.get_proxy
                                <NMActiveConnDBus> (
                                    BusType.SYSTEM,
                                    "org.freedesktop.NetworkManager",
                                    ac_path);
                            if (ac.vpn && ac.state == 2) {
                                active_vpns.set (
                                    (string) ac.connection,
                                    ac_path);
                            }
                        } catch (Error e) {
                            continue;
                        }
                    }
                }
            } catch (Error e) {}

            // Get saved VPN connections
            try {
                var settings =
                    yield Bus.get_proxy<NMSettingsDBus> (
                        BusType.SYSTEM,
                        "org.freedesktop.NetworkManager",
                        "/org/freedesktop/NetworkManager/"
                        + "Settings");
                foreach (var conn_path
                         in settings.list_connections ()) {
                    try {
                        var conn = yield Bus.get_proxy
                            <NMSettingsConnDBus> (
                                BusType.SYSTEM,
                                "org.freedesktop.NetworkManager",
                                conn_path);
                        var s = conn.get_settings ();
                        var conn_s = s.lookup ("connection");
                        if (conn_s == null) continue;
                        var type_var = conn_s.lookup ("type");
                        if (type_var == null
                            || type_var.get_string () != "vpn") {
                            continue;
                        }
                        var id_var = conn_s.lookup ("id");
                        string name = id_var != null
                            ? id_var.get_string () : "VPN";

                        string key = (string) conn_path;
                        if (seen.contains (key)) continue;
                        seen.add (key);

                        bool is_act =
                            active_vpns.has_key (key);
                        ObjectPath ?act_path = is_act
                            ? active_vpns.get (key) : null;

                        new_list.add (VpnInfo () {
                            name = name,
                            conn_path = conn_path,
                            is_active = is_act,
                            active_path = act_path,
                        });
                    } catch (Error e) {
                        continue;
                    }
                }
            } catch (Error e) {
                warning ("load_vpn_list: %s", e.message);
            }
            vpn_list = new_list;
        }

        private async void toggle_vpn () {
            // Find first active VPN to deactivate
            foreach (var vpn in vpn_list) {
                if (vpn.is_active && vpn.active_path != null) {
                    yield deactivate_vpn (vpn.active_path);
                    return;
                }
            }
            // No active VPN — activate first in list
            if (vpn_list.size > 0) {
                yield activate_vpn (vpn_list.get (0).conn_path);
            }
        }

        private async void activate_vpn (
                ObjectPath conn_path) {
            try {
                yield nm_proxy.call_nm (
                    "ActivateConnection",
                    new Variant ("(ooo)",
                        conn_path,
                        new ObjectPath ("/"),
                        new ObjectPath ("/")));
            } catch (Error e) {
                warning ("activate_vpn: %s", e.message);
            }
        }

        private async void deactivate_vpn (
                ObjectPath active_path) {
            try {
                yield nm_proxy.call_nm (
                    "DeactivateConnection",
                    new Variant ("(o)", active_path));
            } catch (Error e) {
                warning ("deactivate_vpn: %s", e.message);
            }
        }

        private async void deactivate_by_conn (
                ObjectPath conn_path) {
            try {
                var nm = nm_proxy.get_nm ();
                if (nm == null) return;
                foreach (var ac_path
                         in nm.active_connections) {
                    try {
                        var ac = yield Bus.get_proxy
                            <NMActiveConnDBus> (
                                BusType.SYSTEM,
                                "org.freedesktop.NetworkManager",
                                ac_path);
                        if (ac.vpn
                            && (string) ac.connection
                                == (string) conn_path) {
                            yield deactivate_vpn (ac_path);
                            return;
                        }
                    } catch (Error e) {
                        continue;
                    }
                }
            } catch (Error e) {
                warning ("deactivate_by_conn: %s",
                         e.message);
            }
        }

        // Submenu

        public override Gtk.Widget ?create_submenu () {
            var box = new Gtk.Box (
                Gtk.Orientation.VERTICAL, 0);
            box.add_css_class ("quick-settings-submenu");
            current_submenu = box;

            build_submenu_header (box);
            refresh_submenu.begin ();

            return box;
        }

        private async void refresh_submenu () {
            if (current_submenu == null) return;
            if (updating_submenu) return;
            updating_submenu = true;

            yield load_vpn_list ();

            if (current_submenu != null) {
                clear_submenu_content (current_submenu);
                build_vpn_list (current_submenu);
            }
            updating_submenu = false;
        }

        private void build_vpn_list (Gtk.Box box) {
            if (vpn_list.size == 0) {
                var empty = new Gtk.Label (
                    _("No VPN connections"));
                empty.add_css_class ("dim-label");
                empty.set_margin_top (8);
                empty.set_margin_bottom (8);
                box.append (empty);
            }

            foreach (var vpn in vpn_list) {
                var vpn_switch = new Gtk.Switch ();
                vpn_switch.set_valign (Gtk.Align.CENTER);
                vpn_switch.set_active (vpn.is_active);

                ObjectPath conn_path = vpn.conn_path;

                // Connect AFTER initial set_active
                Idle.add_once (() => {
                    vpn_switch.state_set.connect ((state) => {
                        connecting = true;
                        if (state) {
                            activate_vpn.begin (conn_path);
                        } else {
                            deactivate_by_conn.begin (
                                conn_path);
                        }
                        return true;
                    });
                });

                var btn = build_submenu_row (
                    "network-vpn-symbolic",
                    vpn.name,
                    vpn_switch);
                btn.clicked.connect (() => {
                    vpn_switch.set_active (
                        !vpn_switch.active);
                });

                box.append (btn);
            }

            // Settings button
            build_settings_button (box);
        }

        private void build_settings_button (Gtk.Box box) {
            string ?cmd = get_settings_command ();
            if (cmd == null) return;

            if (vpn_list.size > 0) {
                box.append (new Gtk.Separator (
                    Gtk.Orientation.HORIZONTAL));
            }

            var btn = build_submenu_row (
                "emblem-system-symbolic",
                _("VPN Settings"));

            btn.clicked.connect (() => {
                try {
                    Process.spawn_command_line_async (cmd);
                    ximper_shell_notification_center_daemon
                        .set_visibility (false);
                } catch (Error e) {
                    warning ("Settings: %s", e.message);
                }
            });

            box.append (btn);
        }

        private static string ?_settings_cmd = null;
        private static bool _settings_checked = false;

        private static string ?get_settings_command () {
            if (_settings_checked) return _settings_cmd;
            _settings_checked = true;
            if (Environment.find_program_in_path (
                    "nm-connection-editor") != null) {
                _settings_cmd = "nm-connection-editor";
            }
            return _settings_cmd;
        }
    }
}
