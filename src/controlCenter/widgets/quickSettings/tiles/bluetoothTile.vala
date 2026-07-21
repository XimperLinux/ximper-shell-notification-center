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
            box.add_css_class ("submenu");

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

            bool seen_known_devices = false;
            bool added_discovered_separator = false;

            foreach (var dev in bt_proxy.devices) {
                bool is_known =
                    BluetoothProxy.is_known_device (dev);
                seen_known_devices |= is_known;
                if (!is_known
                        && seen_known_devices
                        && !added_discovered_separator) {
                    box.append (new Gtk.Separator (
                        Gtk.Orientation.HORIZONTAL));
                    added_discovered_separator = true;
                }

                ObjectPath dev_path = dev.path;
                bool is_connected = dev.connected;
                bool is_busy =
                    bt_proxy.connecting_device != null
                    && (string) bt_proxy.connecting_device
                        == (string) dev.path;

                box.append (build_device_row (
                    dev, dev_path, is_connected, is_busy,
                    is_known));
            }

            // Settings button
            build_settings_button (box);
        }

        private Gtk.Widget build_device_row (
                BluetoothDeviceInfo dev,
                ObjectPath dev_path,
                bool is_connected,
                bool is_busy,
                bool is_known) {
            var container = new Gtk.Box (
                Gtk.Orientation.HORIZONTAL, 8);
            container.add_css_class ("bluetooth-device-row");

            var row = new Gtk.Box (
                Gtk.Orientation.HORIZONTAL, 8);
            row.add_css_class ("submenu-row");

            row.append (new Gtk.Image.from_icon_name (
                BluetoothProxy.get_device_icon (
                    dev.icon_name)));

            var name_label = new Gtk.Label (dev.name);
            name_label.set_ellipsize (
                Pango.EllipsizeMode.END);
            name_label.set_hexpand (true);
            name_label.set_halign (Gtk.Align.START);
            if (is_connected) {
                name_label.add_css_class (
                    "bluetooth-device-connected");
            }
            row.append (name_label);
            row.append (build_device_trailing (dev,
                                               is_connected,
                                               is_busy));

            var btn = new Gtk.Button ();
            btn.set_child (row);
            btn.add_css_class ("flat");
            btn.set_hexpand (true);
            btn.set_sensitive (!is_busy);
            btn.tooltip_text = is_connected
                ? _("Disconnect")
                : _("Connect");

            btn.clicked.connect (() => {
                if (is_connected) {
                    bt_proxy.disconnect_device.begin (
                        dev_path);
                } else {
                    bt_proxy.connect_device.begin (
                        dev_path);
                }
            });

            container.append (btn);

            if (is_known) {
                var forget_button =
                    build_forget_button (dev_path);
                forget_button.set_sensitive (!is_busy);
                container.append (forget_button);
            }

            return container;
        }

        private Gtk.Widget build_device_trailing (
                BluetoothDeviceInfo dev,
                bool is_connected,
                bool is_busy) {
            if (is_busy) {
                var spinner = new Gtk.Spinner ();
                spinner.start ();
                return spinner;
            }

            var trailing = new Gtk.Box (
                Gtk.Orientation.HORIZONTAL, 6);
            trailing.set_valign (Gtk.Align.CENTER);

            if (is_connected && dev.battery_percentage >= 0) {
                var battery_icon = new Gtk.Image.from_icon_name (
                    get_battery_icon_name (
                        dev.battery_percentage));
                battery_icon.add_css_class (
                    "bluetooth-device-battery-icon");
                trailing.append (battery_icon);

                var battery_label = new Gtk.Label (
                    "%d%%".printf (dev.battery_percentage));
                battery_label.add_css_class ("dim-label");
                trailing.append (battery_label);
            }

            return trailing;
        }

        private Gtk.Button build_forget_button (
                ObjectPath device_path) {
            var button = new Gtk.Button.from_icon_name (
                "edit-delete-symbolic");
            button.add_css_class ("flat");
            button.add_css_class ("circular");
            button.add_css_class ("bluetooth-forget-button");
            button.tooltip_text = _("Forget");

            button.clicked.connect (() => {
                bt_proxy.forget_device (device_path);
            });

            return button;
        }

        private static string get_battery_icon_name (
                int percentage) {
            percentage = int.max (
                0, int.min (100, percentage));
            int level = ((percentage + 5) / 10) * 10;

            if (level == 0) {
                return "battery-caution-symbolic";
            }

            return "battery-level-%d-symbolic".printf (level);
        }

        private void build_settings_button (Gtk.Box box) {
            string ?cmd = get_settings_command ();
            if (cmd == null) return;

            if (bt_proxy.devices.size > 0) {
                box.append (new Gtk.Separator (
                    Gtk.Orientation.HORIZONTAL));
            }

            var btn = build_submenu_row (
                "emblem-system-symbolic",
                _("Bluetooth Settings"));

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
