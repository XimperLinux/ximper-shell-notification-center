namespace XimperShellNotificationCenter {
    [DBus (name = "org.freedesktop.UPower.Device")]
    interface UPowerDevice : Object {
        [DBus (name = "Type")]
        public abstract uint device_type { get; }
        public abstract bool is_present { get; }
        public abstract double percentage { get; }
        public abstract uint state { get; }
    }

    [DBus (name = "org.freedesktop.login1.Manager")]
    interface Login1PowerManager : Object {
        public abstract string can_power_off () throws Error;
        public abstract string can_reboot () throws Error;
        public abstract string can_suspend () throws Error;
        public abstract string can_hibernate () throws Error;

        public abstract void power_off (bool interactive) throws Error;
        public abstract void reboot (bool interactive) throws Error;
        public abstract void suspend (bool interactive) throws Error;
        public abstract void hibernate (bool interactive) throws Error;
    }

    public class ControlCenterHeader : Gtk.Box {
        private const uint UPOWER_DEVICE_TYPE_BATTERY = 2;
        private const uint UPOWER_DEVICE_STATE_CHARGING = 1;
        private const uint UPOWER_DEVICE_STATE_FULLY_CHARGED = 4;
        private const uint UPOWER_DEVICE_STATE_PENDING_CHARGE = 5;

        private Gtk.Box battery_box;
        private Gtk.Image battery_icon;
        private Gtk.Label battery_label;
        private Gtk.Button settings_button;
        private Gtk.Button power_button;
        private Gtk.Revealer power_revealer;
        private Gtk.Box power_menu_box;

        private UPowerDevice ?battery = null;
        private DBusProxy ?battery_proxy = null;
        private Login1PowerManager ?login1 = null;

        public ControlCenterHeader () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            add_css_class ("control-center-header");

            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            row.add_css_class ("control-center-header-row");

            var left = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            left.set_hexpand (true);
            left.set_halign (Gtk.Align.START);
            left.set_valign (Gtk.Align.CENTER);

            battery_box = build_battery_box ();
            left.append (battery_box);

            settings_button = build_icon_button (
                "preferences-system-symbolic",
                _("Settings"));
            settings_button.clicked.connect (open_settings);
            left.append (settings_button);

            var right = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            right.set_halign (Gtk.Align.END);
            right.set_valign (Gtk.Align.CENTER);

            var lock_button = build_icon_button (
                "system-lock-screen-symbolic",
                _("Lock"));
            lock_button.clicked.connect (lock_session);
            right.append (lock_button);

            power_button = build_power_button ();
            right.append (power_button);

            row.append (left);
            row.append (right);
            append (row);

            power_revealer = new Gtk.Revealer ();
            power_revealer.set_transition_type (
                Gtk.RevealerTransitionType.SLIDE_DOWN);
            power_revealer.set_transition_duration (200);
            power_menu_box = new Gtk.Box (
                Gtk.Orientation.VERTICAL, 0);
            power_menu_box.add_css_class ("submenu");
            power_menu_box.add_css_class ("control-center-power-menu");
            power_revealer.set_child (power_menu_box);
            append (power_revealer);

            connect_battery ();
            connect_login1 ();
            update_settings_visibility ();
            update_power_menu ();
        }

        private Gtk.Box build_battery_box () {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            box.add_css_class ("control-center-header-battery");
            box.set_valign (Gtk.Align.CENTER);

            battery_icon = new Gtk.Image.from_icon_name (
                "battery-symbolic");
            battery_label = new Gtk.Label ("");
            battery_label.add_css_class ("caption");

            box.append (battery_icon);
            box.append (battery_label);
            box.set_visible (false);
            return box;
        }

        private Gtk.Button build_icon_button (string icon_name,
                                              string tooltip) {
            var button = new Gtk.Button ();
            button.add_css_class ("control-center-header-button");
            button.add_css_class ("circular");
            button.tooltip_text = tooltip;
            var image = new Gtk.Image.from_icon_name (icon_name);
            button.set_child (image);
            return button;
        }

        private Gtk.Button build_power_button () {
            var button = build_icon_button (
                "system-shutdown-symbolic",
                _("Power"));
            button.clicked.connect (() => {
                update_power_menu ();
                power_revealer.set_reveal_child (
                    !power_revealer.reveal_child);
            });
            return button;
        }

        private void connect_battery () {
            try {
                battery = Bus.get_proxy_sync (
                    BusType.SYSTEM,
                    "org.freedesktop.UPower",
                    "/org/freedesktop/UPower/devices/DisplayDevice");
                battery_proxy = battery as DBusProxy;
                if (battery_proxy != null) {
                    battery_proxy.g_properties_changed.connect (
                        () => update_battery ());
                }
                update_battery ();
            } catch (Error e) {
                debug ("UPower display device not available: %s",
                       e.message);
                battery_box.set_visible (false);
            }
        }

        private void connect_login1 () {
            try {
                login1 = Bus.get_proxy_sync (
                    BusType.SYSTEM,
                    "org.freedesktop.login1",
                    "/org/freedesktop/login1");
            } catch (Error e) {
                warning ("logind power actions not available: %s",
                         e.message);
            }
        }

        private void update_battery () {
            if (battery == null) {
                battery_box.set_visible (false);
                return;
            }

            bool visible = battery.is_present
                && battery.device_type == UPOWER_DEVICE_TYPE_BATTERY;
            battery_box.set_visible (visible);
            if (!visible) {
                return;
            }

            int percentage = (int) Math.round (battery.percentage);
            battery_label.set_text ("%d%%".printf (percentage));
            battery_icon.set_from_icon_name (
                get_battery_icon_name (percentage, battery.state));
        }

        private static string get_battery_icon_name (int percentage,
                                                     uint state) {
            int level = get_battery_icon_level (percentage);

            switch (state) {
                case UPOWER_DEVICE_STATE_CHARGING:
                    if (level == 100) {
                        return "battery-level-100-charged-symbolic";
                    }
                    return "battery-level-%d-charging-symbolic".printf (
                        level);
                case UPOWER_DEVICE_STATE_FULLY_CHARGED:
                    return "battery-level-100-charged-symbolic";
                case UPOWER_DEVICE_STATE_PENDING_CHARGE:
                    return "battery-level-%d-plugged-in-symbolic".printf (
                        level);
                default:
                    if (level == 0) {
                        return "battery-caution-symbolic";
                    }
                    return "battery-level-%d-symbolic".printf (level);
            }
        }

        private static int get_battery_icon_level (int percentage) {
            percentage = int.max (0, int.min (100, percentage));
            return ((percentage + 5) / 10) * 10;
        }

        private void update_settings_visibility () {
            settings_button.set_visible (
                Environment.find_program_in_path ("tuner") != null);
        }

        private void open_settings () {
            try {
                Process.spawn_command_line_async ("tuner");
                control_center.set_visibility (false);
            } catch (Error e) {
                warning ("Failed to launch tuner: %s", e.message);
                settings_button.set_visible (false);
            }
        }

        private void lock_session () {
            try {
                Process.spawn_command_line_async (
                    "loginctl lock-session");
                control_center.set_visibility (false);
            } catch (Error e) {
                warning ("Failed to lock session: %s", e.message);
            }
        }

        private void update_power_menu () {
            remove_power_menu_children ();

            string ?session_id =
                Environment.get_variable ("XDG_SESSION_ID");
            if (session_id != null && session_id.length > 0) {
                add_power_action (
                    "system-log-out-symbolic",
                    _("Log Out"),
                    () => logout_session (session_id));
            }

            if (can_login1_action ("suspend")) {
                add_power_action (
                    "system-suspend-symbolic",
                    _("Suspend"),
                    () => run_login1_action ("suspend"));
            }
            if (can_login1_action ("hibernate")) {
                add_power_action (
                    "system-suspend-symbolic",
                    _("Hibernate"),
                    () => run_login1_action ("hibernate"));
            }
            if (can_login1_action ("reboot")) {
                add_power_action (
                    "system-reboot-symbolic",
                    _("Restart"),
                    () => run_login1_action ("reboot"));
            }
            if (can_login1_action ("power-off")) {
                add_power_action (
                    "system-shutdown-symbolic",
                    _("Power Off"),
                    () => run_login1_action ("power-off"));
            }

            power_button.set_visible (
                power_menu_box.get_first_child () != null);
        }

        private void remove_power_menu_children () {
            for (Gtk.Widget ?child = power_menu_box.get_first_child ();
                 child != null;) {
                Gtk.Widget next = child.get_next_sibling ();
                power_menu_box.remove (child);
                child = next;
            }
        }

        private delegate void PowerActionCallback ();

        private void add_power_action (string icon_name,
                                       string label,
                                       owned PowerActionCallback callback) {
            var button = new Gtk.Button ();
            button.add_css_class ("flat");

            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            row.add_css_class ("submenu-row");
            var image = new Gtk.Image.from_icon_name (icon_name);
            row.append (image);

            var row_label = new Gtk.Label (label);
            row_label.set_halign (Gtk.Align.START);
            row_label.set_hexpand (true);
            row.append (row_label);

            button.set_child (row);
            button.clicked.connect (() => callback ());
            power_menu_box.append (button);
        }

        public void close_power_menu () {
            power_revealer.set_reveal_child (false);
        }

        private bool can_login1_action (string action) {
            if (login1 == null) {
                return false;
            }

            try {
                string result;
                switch (action) {
                    case "power-off":
                        result = login1.can_power_off ();
                        break;
                    case "reboot":
                        result = login1.can_reboot ();
                        break;
                    case "suspend":
                        result = login1.can_suspend ();
                        break;
                    case "hibernate":
                        result = login1.can_hibernate ();
                        break;
                    default:
                        return false;
                }
                return result == "yes" || result == "challenge";
            } catch (Error e) {
                warning ("Failed to query logind action %s: %s",
                         action, e.message);
                return false;
            }
        }

        private void logout_session (string session_id) {
            power_revealer.set_reveal_child (false);
            control_center.set_visibility (false);
            string cmd = "loginctl terminate-session %s".printf (
                Shell.quote (session_id));
            run_command.begin (cmd);
        }

        private void run_login1_action (string action) {
            if (login1 == null) {
                return;
            }

            power_revealer.set_reveal_child (false);
            control_center.set_visibility (false);
            try {
                switch (action) {
                    case "power-off":
                        login1.power_off (false);
                        break;
                    case "reboot":
                        login1.reboot (false);
                        break;
                    case "suspend":
                        login1.suspend (false);
                        break;
                    case "hibernate":
                        login1.hibernate (false);
                        break;
                }
            } catch (Error e) {
                warning ("Failed to run logind action %s: %s",
                         action, e.message);
            }
        }

        private async void run_command (string command) {
            string msg;
            yield Functions.execute_command (command, {}, out msg);
        }
    }
}
