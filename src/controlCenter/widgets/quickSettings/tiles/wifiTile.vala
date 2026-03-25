namespace XimperShellNotificationCenter.Widgets {

    private struct ApInfo {
        string ssid;
        uint8 strength;
        bool secured;
        bool is_active;
        ObjectPath ap_path;
        bool has_saved;
        ObjectPath ?saved_path;
    }

    public class WifiTile : QuickSettingsTile {
        private NetworkManagerProxy nm_proxy;
        private ObjectPath ?wifi_dev_path = null;
        private string ?active_ssid = null;
        private uint8 active_strength = 0;
        private Gee.HashSet<string> ?saved_ssids = null;
        private Gee.HashMap<string, ObjectPath> ?saved_map = null;
        private uint sync_timeout = 0;
        private Gtk.Box ?current_submenu = null;
        private bool connecting = false;
        private bool updating_submenu = false;

        public WifiTile (Json.Object ?cfg) {
            base ("network-wireless-offline-symbolic",
                  _("Wi-Fi"));
            setup_arrow ();
            nm_proxy = NetworkManagerProxy.get_instance ();
            nm_proxy.state_changed.connect (schedule_sync);
            init_wifi.begin ();
        }

        private void schedule_sync () {
            if (sync_timeout != 0) {
                Source.remove (sync_timeout);
            }
            sync_timeout = Timeout.add (1000, () => {
                sync_timeout = 0;
                on_debounced_update.begin ();
                return Source.REMOVE;
            });
        }

        private async void on_debounced_update () {
            string ?old_ssid = active_ssid;
            yield sync_state ();

            if (old_ssid != active_ssid) {
                connecting = false;
                refresh_submenu.begin ();
            } else if (!connecting) {
                refresh_submenu.begin ();
            }
        }

        private async void init_wifi () {
            wifi_dev_path =
                yield nm_proxy.get_wifi_device ();
            yield sync_state ();
        }

        public override bool is_available () {
            return nm_proxy.available && nm_proxy.has_wifi;
        }

        public override void on_toggle () {
            nm_proxy.set_wireless_enabled (
                !nm_proxy.get_wireless_enabled ());
        }

        public override void on_cc_visibility_change (
                bool visible) {
            if (visible) {
                sync_state.begin ();
                scan.begin ();
            } else {
                current_submenu = null;
                connecting = false;
            }
        }

        private async void sync_state () {
            if (wifi_dev_path == null && nm_proxy.available) {
                wifi_dev_path =
                    yield nm_proxy.get_wifi_device ();
            }
            bool enabled = nm_proxy.get_wireless_enabled ();
            active = enabled;

            if (!enabled) {
                icon.set_from_icon_name (
                    "network-wireless-disabled-symbolic");
                set_subtitle (_("Disabled"));
                active_ssid = null;
                return;
            }

            active_ssid = null;
            active_strength = 0;
            if (wifi_dev_path != null) {
                try {
                    var wireless =
                        yield Bus.get_proxy<NMWirelessDBus> (
                            BusType.SYSTEM,
                            "org.freedesktop.NetworkManager",
                            wifi_dev_path);
                    ObjectPath ap_path =
                        wireless.active_access_point;
                    if (ap_path != null
                        && ap_path != "/"
                        && ap_path != "") {
                        var ap =
                            yield Bus.get_proxy<NMAccessPointDBus> (
                                BusType.SYSTEM,
                                "org.freedesktop.NetworkManager",
                                ap_path);
                        active_ssid =
                            NetworkManagerProxy.ssid_to_string (
                                ap.ssid);
                        active_strength = ap.strength;
                    }
                } catch (Error e) {}
            }

            if (active_ssid != null && active_ssid.length > 0) {
                icon.set_from_icon_name (
                    NetworkManagerProxy.get_signal_icon (
                        active_strength));
                set_subtitle (active_ssid);
                connecting = false;
            } else if (!connecting) {
                icon.set_from_icon_name (
                    "network-wireless-offline-symbolic");
                set_subtitle (_("Not Connected"));
            }
        }

        private async void scan () {
            if (wifi_dev_path == null) return;
            try {
                var wireless =
                    yield Bus.get_proxy<NMWirelessDBus> (
                        BusType.SYSTEM,
                        "org.freedesktop.NetworkManager",
                        wifi_dev_path);
                wireless.request_scan (
                    new HashTable<string, Variant> (
                        str_hash, str_equal));
            } catch (Error e) {}
        }

        private async ApInfo[] get_access_points () {
            ApInfo[] result = {};
            if (wifi_dev_path == null) return result;

            yield load_saved_connections ();

            try {
                var wireless =
                    yield Bus.get_proxy<NMWirelessDBus> (
                        BusType.SYSTEM,
                        "org.freedesktop.NetworkManager",
                        wifi_dev_path);
                var ap_paths =
                    wireless.get_all_access_points ();

                var best = new Gee.HashMap<string, ApInfo?> ();

                foreach (var ap_path in ap_paths) {
                    try {
                        var ap =
                            yield Bus.get_proxy<NMAccessPointDBus> (
                                BusType.SYSTEM,
                                "org.freedesktop.NetworkManager",
                                ap_path);
                        string ssid =
                            NetworkManagerProxy.ssid_to_string (
                                ap.ssid);
                        if (ssid == null || ssid.length == 0) {
                            continue;
                        }

                        bool secured =
                            ap.wpa_flags != 0
                            || ap.rsn_flags != 0;
                        bool is_act = active_ssid != null
                            && ssid == active_ssid;
                        bool has_saved =
                            saved_ssids != null
                            && saved_ssids.contains (ssid);
                        ObjectPath ?sp = has_saved
                            && saved_map != null
                            ? saved_map.get (ssid) : null;

                        var info = ApInfo () {
                            ssid = ssid,
                            strength = ap.strength,
                            secured = secured,
                            is_active = is_act,
                            ap_path = ap_path,
                            has_saved = has_saved,
                            saved_path = sp,
                        };

                        if (!best.has_key (ssid)
                            || best.get (ssid).strength
                                < ap.strength) {
                            best.set (ssid, info);
                        }
                    } catch (Error e) {
                        continue;
                    }
                }

                var sorted = new Gee.ArrayList<ApInfo?> ();
                foreach (var v in best.values) {
                    sorted.add (v);
                }
                sorted.sort ((a, b) => {
                    if (a.is_active != b.is_active) {
                        return a.is_active ? -1 : 1;
                    }
                    return (int) b.strength
                        - (int) a.strength;
                });

                foreach (var info in sorted) {
                    result += info;
                }
            } catch (Error e) {
                warning ("get_access_points: %s",
                         e.message);
            }

            return result;
        }

        private async void load_saved_connections () {
            saved_ssids = new Gee.HashSet<string> ();
            saved_map =
                new Gee.HashMap<string, ObjectPath> ();
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
                        var conn =
                            yield Bus.get_proxy<NMSettingsConnDBus> (
                                BusType.SYSTEM,
                                "org.freedesktop.NetworkManager",
                                conn_path);
                        var s = conn.get_settings ();
                        var wifi_s = s.lookup (
                            "802-11-wireless");
                        if (wifi_s == null) continue;
                        var ssid_var = wifi_s.lookup ("ssid");
                        if (ssid_var == null) continue;
                        string ssid =
                            NetworkManagerProxy.ssid_to_string (
                                ssid_var.get_data_as_bytes ()
                                    .get_data ());
                        if (ssid.length > 0) {
                            saved_ssids.add (ssid);
                            saved_map.set (ssid, conn_path);
                        }
                    } catch (Error e) {
                        continue;
                    }
                }
            } catch (Error e) {
                warning ("load_saved: %s", e.message);
            }
        }

        // Submenu

        public override Gtk.Widget ?create_submenu () {
            if (!nm_proxy.get_wireless_enabled ()) {
                current_submenu = null;
                return null;
            }

            var box = new Gtk.Box (
                Gtk.Orientation.VERTICAL, 0);
            box.add_css_class ("quick-settings-submenu");
            current_submenu = box;

            refresh_submenu.begin ();

            return box;
        }

        private async void refresh_submenu () {
            if (current_submenu == null) return;
            if (updating_submenu) return;
            updating_submenu = true;

            var aps = yield get_access_points ();

            if (current_submenu != null) {
                for (var child =
                         current_submenu.get_first_child ();
                     child != null;) {
                    var next = child.get_next_sibling ();
                    current_submenu.remove (child);
                    child = next;
                }
                build_ap_list (current_submenu, aps);
            }
            updating_submenu = false;
        }

        private void build_ap_list (
                Gtk.Box box, ApInfo[] aps) {
            foreach (var ap in aps) {
                var row = new Gtk.Box (
                    Gtk.Orientation.HORIZONTAL, 8);
                row.add_css_class ("submenu-row");

                var row_icon = new Gtk.Image.from_icon_name (
                    NetworkManagerProxy.get_signal_icon (
                        ap.strength));
                var row_label = new Gtk.Label (ap.ssid);
                row_label.set_ellipsize (
                    Pango.EllipsizeMode.END);
                row_label.set_hexpand (true);
                row_label.set_halign (Gtk.Align.START);

                var status_stack = new Gtk.Stack ();
                status_stack.set_transition_type (
                    Gtk.StackTransitionType.CROSSFADE);
                var check_img = new Gtk.Image.from_icon_name (
                    "object-select-symbolic");
                var lock_img = new Gtk.Image.from_icon_name (
                    "network-wireless-encrypted-symbolic");
                var spinner = new Gtk.Spinner ();
                var empty = new Gtk.Box (
                    Gtk.Orientation.HORIZONTAL, 0);
                status_stack.add_named (check_img, "check");
                status_stack.add_named (lock_img, "lock");
                status_stack.add_named (spinner, "spinner");
                status_stack.add_named (empty, "empty");

                if (ap.is_active) {
                    status_stack.set_visible_child_name (
                        "check");
                } else if (ap.secured && !ap.has_saved) {
                    status_stack.set_visible_child_name (
                        "lock");
                } else {
                    status_stack.set_visible_child_name (
                        "empty");
                }

                row.append (row_icon);
                row.append (row_label);
                row.append (status_stack);

                var item_box = new Gtk.Box (
                    Gtk.Orientation.VERTICAL, 0);
                var btn = new Gtk.Button ();
                btn.set_child (row);
                btn.add_css_class ("flat");
                item_box.append (btn);

                if (ap.secured && !ap.has_saved
                    && !ap.is_active) {
                    build_password_row (item_box, btn,
                        status_stack, spinner, ap);
                } else if (!ap.is_active) {
                    build_connect_handler (btn,
                        status_stack, spinner, ap);
                }

                box.append (item_box);
            }

            // Settings button
            build_settings_button (box);
        }

        private void build_password_row (
                Gtk.Box item_box, Gtk.Button btn,
                Gtk.Stack status_stack, Gtk.Spinner spinner,
                ApInfo ap) {
            var pwd_revealer = new Gtk.Revealer ();
            pwd_revealer.set_transition_type (
                Gtk.RevealerTransitionType.SLIDE_DOWN);
            pwd_revealer.set_transition_duration (150);

            var pwd_box = new Gtk.Box (
                Gtk.Orientation.HORIZONTAL, 4);
            pwd_box.set_margin_start (8);
            pwd_box.set_margin_end (8);
            pwd_box.set_margin_bottom (4);

            var pwd_entry = new Gtk.PasswordEntry ();
            pwd_entry.set_hexpand (true);
            pwd_entry.placeholder_text = _("Password");
            pwd_entry.set_show_peek_icon (true);

            var connect_btn = new Gtk.Button.with_label (
                _("Connect"));
            connect_btn.set_sensitive (false);

            pwd_entry.notify["text"].connect (() => {
                connect_btn.set_sensitive (
                    pwd_entry.get_text ().strip ().length >= 8);
            });

            pwd_box.append (pwd_entry);
            pwd_box.append (connect_btn);
            pwd_revealer.set_child (pwd_box);
            item_box.append (pwd_revealer);

            btn.clicked.connect (() => {
                pwd_revealer.set_reveal_child (
                    !pwd_revealer.get_reveal_child ());
                if (pwd_revealer.get_reveal_child ()) {
                    pwd_entry.grab_focus ();
                }
            });

            string ssid = ap.ssid;
            connect_btn.clicked.connect (() => {
                string pwd =
                    pwd_entry.get_text ().strip ();
                if (pwd.length > 0) {
                    pwd_revealer.set_reveal_child (false);
                    start_connecting (status_stack, spinner);
                    connect_new.begin (ssid, pwd);
                }
            });

            pwd_entry.activate.connect (() => {
                connect_btn.clicked ();
            });
        }

        private void build_connect_handler (
                Gtk.Button btn, Gtk.Stack status_stack,
                Gtk.Spinner spinner, ApInfo ap) {
            ObjectPath ?sp = ap.saved_path;
            ObjectPath ap_path = ap.ap_path;
            string ssid = ap.ssid;
            bool secured = ap.secured;

            btn.clicked.connect (() => {
                start_connecting (status_stack, spinner);
                if (sp != null) {
                    activate_saved.begin (sp, ap_path);
                } else if (!secured) {
                    connect_new.begin (ssid, "");
                }
            });
        }

        private void start_connecting (
                Gtk.Stack stack, Gtk.Spinner spinner) {
            stack.set_visible_child_name ("spinner");
            spinner.start ();
            connecting = true;
            set_subtitle (_("Connecting\u2026"));
        }

        private void build_settings_button (Gtk.Box box) {
            string ?cmd = get_settings_command ();
            if (cmd == null) return;

            box.append (new Gtk.Separator (
                Gtk.Orientation.HORIZONTAL));

            var row = new Gtk.Box (
                Gtk.Orientation.HORIZONTAL, 8);
            row.add_css_class ("submenu-row");
            row.append (new Gtk.Image.from_icon_name (
                "emblem-system-symbolic"));
            var label = new Gtk.Label (
                _("Network Settings"));
            label.set_hexpand (true);
            label.set_halign (Gtk.Align.START);
            row.append (label);

            var btn = new Gtk.Button ();
            btn.set_child (row);
            btn.add_css_class ("flat");

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

        private static string ?get_settings_command () {
            try {
                string output;
                Process.spawn_command_line_sync (
                    "which nm-connection-editor",
                    out output, null, null);
                if (output.strip ().length > 0) {
                    return "nm-connection-editor";
                }
            } catch (SpawnError e) {}
            return null;
        }

        // Connection methods

        private async void activate_saved (
                ObjectPath conn_path,
                ObjectPath ap_path) {
            if (wifi_dev_path == null) return;
            try {
                yield nm_proxy.call_nm (
                    "ActivateConnection",
                    new Variant ("(ooo)",
                        conn_path, wifi_dev_path, ap_path));
            } catch (Error e) {
                warning ("activate_saved: %s", e.message);
                connecting = false;
            }
        }

        private async void connect_new (
                string ssid, string psk) {
            if (wifi_dev_path == null) return;
            try {
                yield nm_proxy.call_nm (
                    "AddAndActivateConnection",
                    new Variant ("(a{sa{sv}}oo)",
                        build_wifi_settings (ssid, psk),
                        wifi_dev_path,
                        new ObjectPath ("/")));
            } catch (Error e) {
                warning ("connect_new: %s", e.message);
                connecting = false;
            }
        }

        private HashTable<string, HashTable<string, Variant>>
                build_wifi_settings (
                    string ssid, string psk) {
            var result =
                new HashTable<string, HashTable<string, Variant>> (
                    str_hash, str_equal);

            var conn = new HashTable<string, Variant> (
                str_hash, str_equal);
            conn.insert ("type",
                new Variant.string ("802-11-wireless"));
            conn.insert ("id",
                new Variant.string (ssid));
            string user = Environment.get_user_name ();
            var perms = new VariantBuilder (
                new VariantType ("as"));
            perms.add ("s", "user:%s:".printf (user));
            conn.insert ("permissions", perms.end ());
            result.insert ("connection", conn);

            var wifi = new HashTable<string, Variant> (
                str_hash, str_equal);
            var ssid_builder = new VariantBuilder (
                new VariantType ("ay"));
            for (int i = 0; i < ssid.data.length; i++) {
                ssid_builder.add ("y", ssid.data[i]);
            }
            wifi.insert ("ssid", ssid_builder.end ());
            result.insert ("802-11-wireless", wifi);

            if (psk.length > 0) {
                var sec = new HashTable<string, Variant> (
                    str_hash, str_equal);
                sec.insert ("key-mgmt",
                    new Variant.string ("wpa-psk"));
                sec.insert ("psk",
                    new Variant.string (psk));
                result.insert (
                    "802-11-wireless-security", sec);
            }

            return result;
        }
    }
}
