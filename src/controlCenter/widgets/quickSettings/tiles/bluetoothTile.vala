namespace XimperShellNotificationCenter.Widgets {
    public class BluetoothTile : QuickSettingsTile {
        private BluetoothProxy bt_proxy;
        private uint sync_timeout = 0;
        private static string ?settings_cmd = null;
        private static bool settings_cmd_checked = false;

        ~BluetoothTile () {
            if (sync_timeout != 0) {
                Source.remove (sync_timeout);
            }
        }

        public BluetoothTile (Json.Object ?cfg) {
            base ("bluetooth-active-symbolic",
                  _("Bluetooth"));
            setup_arrow ();

            bt_proxy = BluetoothProxy.get_instance ();
            bt_proxy.state_changed.connect (schedule_sync);
            bt_proxy.devices_changed.connect (() => {
                sync_subtitle ();
                submenu_update_requested ();
            });

            sync_subtitle ();
        }

        public override bool is_available () {
            return bt_proxy.available;
        }

        public override void on_toggle () {
            bt_proxy.set_powered (!bt_proxy.powered);
        }

        public override void on_cc_visibility_change (
                bool visible) {
            if (visible) {
                sync_subtitle ();
            } else {
                bt_proxy.stop_discovery ();
            }
        }

        private void schedule_sync () {
            if (sync_timeout != 0) {
                Source.remove (sync_timeout);
            }
            sync_timeout = Timeout.add (500, () => {
                sync_timeout = 0;
                sync_subtitle ();
                submenu_update_requested ();
                return Source.REMOVE;
            });
        }

        private void sync_subtitle () {
            active = bt_proxy.powered;

            if (!bt_proxy.powered) {
                icon.set_from_icon_name (
                    "bluetooth-disabled-symbolic");
                set_subtitle (_("Disabled"));
                return;
            }

            icon.set_from_icon_name (
                "bluetooth-active-symbolic");

            string ?connected_name =
                bt_proxy.get_connected_device_name ();
            if (connected_name != null) {
                set_subtitle (connected_name);
            } else {
                set_subtitle (_("Not Connected"));
            }
        }

        // Submenu

        public override Gtk.Widget ?create_submenu () {
            var box = new Gtk.Box (
                Gtk.Orientation.VERTICAL, 0);
            box.add_css_class ("quick-settings-submenu");

            build_submenu_header (box);
            bt_proxy.start_discovery ();
            build_device_list (box);

            return box;
        }

        private void build_device_list (Gtk.Box box) {
            if (bt_proxy.devices.size == 0) {
                var empty = new Gtk.Label (
                    _("Searching for devices…"));
                empty.add_css_class ("dim-label");
                empty.set_margin_top (8);
                empty.set_margin_bottom (8);
                box.append (empty);
            }

            foreach (var dev in bt_proxy.devices) {
                var row = new Gtk.Box (
                    Gtk.Orientation.HORIZONTAL, 8);
                row.add_css_class ("submenu-row");

                var row_icon = new Gtk.Image.from_icon_name (
                    BluetoothProxy.get_device_icon (
                        dev.icon_name));
                var row_label = new Gtk.Label (dev.name);
                row_label.set_ellipsize (
                    Pango.EllipsizeMode.END);
                row_label.set_hexpand (true);
                row_label.set_halign (Gtk.Align.START);

                row.append (row_icon);
                row.append (row_label);

                ObjectPath dev_path = dev.path;
                bool is_connected = dev.connected;
                bool is_busy =
                    bt_proxy.connecting_device != null
                    && (string) bt_proxy.connecting_device
                        == (string) dev.path;

                if (is_busy) {
                    var spinner = new Gtk.Spinner ();
                    spinner.start ();
                    row.append (spinner);
                } else {
                    var action_label = new Gtk.Label (
                        is_connected
                            ? _("Disconnect")
                            : _("Connect"));
                    action_label.add_css_class ("dim-label");
                    row.append (action_label);
                }

                var btn = new Gtk.Button ();
                btn.set_child (row);
                btn.add_css_class ("flat");
                btn.set_sensitive (!is_busy);

                btn.clicked.connect (() => {
                    if (is_connected) {
                        bt_proxy.disconnect_device.begin (
                            dev_path);
                    } else {
                        bt_proxy.connect_device.begin (
                            dev_path);
                    }
                });

                box.append (btn);
            }

            // Settings button
            build_settings_button (box);
        }

        private void build_settings_button (Gtk.Box box) {
            string ?cmd = get_settings_command ();
            if (cmd == null) return;

            if (bt_proxy.devices.size > 0) {
                box.append (new Gtk.Separator (
                    Gtk.Orientation.HORIZONTAL));
            }

            var row = new Gtk.Box (
                Gtk.Orientation.HORIZONTAL, 8);
            row.add_css_class ("submenu-row");
            row.append (new Gtk.Image.from_icon_name (
                "emblem-system-symbolic"));
            var label = new Gtk.Label (
                _("Bluetooth Settings"));
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
                    warning ("BT Settings: %s", e.message);
                }
            });

            box.append (btn);
        }

        private static string ?get_settings_command () {
            if (settings_cmd_checked) return settings_cmd;
            settings_cmd_checked = true;

            if (Environment.find_program_in_path (
                    "blueman-manager") != null) {
                settings_cmd = "blueman-manager";
                return settings_cmd;
            }
            return null;
        }
    }
}
