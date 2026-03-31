namespace XimperShellNotificationCenter.Widgets {
    [DBus (name = "net.hadess.PowerProfiles")]
    interface PowerProfilesDBus : Object {
        public abstract string active_profile { owned get; set; }
        public abstract HashTable<string, Variant>[] profiles {
            owned get;
        }
    }

    public class PowerProfilesTile : QuickSettingsTile {
        private PowerProfilesDBus ?proxy = null;
        private DBusProxy ?raw_proxy = null;

        private string[] profile_names = {};

        public PowerProfilesTile (Json.Object ?cfg) {
            base ("power-profile-balanced-symbolic",
                  _("Power Mode"));
            setup_arrow ();
            connect_dbus.begin ();
        }

        private async void connect_dbus () {
            try {
                proxy = yield Bus.get_proxy (BusType.SYSTEM,
                    "net.hadess.PowerProfiles",
                    "/net/hadess/PowerProfiles");
                raw_proxy = proxy as DBusProxy;

                load_profiles ();
                sync_state ();

                raw_proxy.g_properties_changed.connect (
                    on_properties_changed);
            } catch (Error e) {
                warning ("PowerProfiles D-Bus not available: %s",
                         e.message);
                set_visible (false);
            }
        }

        private void load_profiles () {
            if (proxy == null) return;
            profile_names = {};
            foreach (var profile in proxy.profiles) {
                Variant ?v = profile.lookup ("Profile");
                if (v != null) {
                    profile_names += v.get_string ();
                }
            }
        }

        private void on_properties_changed (
                Variant changed, string[] invalidated) {
            var iter = changed.iterator ();
            string key;
            Variant val;
            while (iter.next ("{sv}", out key, out val)) {
                if (key == "ActiveProfile") {
                    sync_state ();
                    submenu_update_requested ();
                } else if (key == "Profiles") {
                    load_profiles ();
                    submenu_update_requested ();
                }
            }
        }

        private void sync_state () {
            if (proxy == null) return;
            string profile = proxy.active_profile;
            active = (profile != "balanced");
            set_subtitle (get_profile_label (profile));
            update_icon (profile);
        }

        private void update_icon (string profile) {
            icon.set_from_icon_name (get_profile_icon (profile));
        }

        private static string get_profile_icon (string profile) {
            switch (profile) {
                case "performance":
                    return "power-profile-performance-symbolic";
                case "power-saver":
                    return "power-profile-power-saver-symbolic";
                default:
                    return "power-profile-balanced-symbolic";
            }
        }

        private string get_profile_label (string profile) {
            switch (profile) {
                case "performance":
                    return _("Performance");
                case "balanced":
                    return _("Balanced");
                case "power-saver":
                    return _("Power Saver");
                default:
                    return profile;
            }
        }

        public override void on_toggle () {
            if (proxy == null) return;

            string current = proxy.active_profile;
            // Cycle: balanced → performance → power-saver
            string next;
            if (current == "balanced") {
                next = "performance";
            } else if (current == "performance") {
                next = "power-saver";
            } else {
                next = "balanced";
            }

            set_profile.begin (next);
        }

        private async void set_profile (string profile) {
            if (raw_proxy == null) return;
            try {
                yield raw_proxy.call (
                    "org.freedesktop.DBus.Properties.Set",
                    new Variant ("(ssv)",
                        "net.hadess.PowerProfiles",
                        "ActiveProfile",
                        new Variant.string (profile)),
                    DBusCallFlags.NONE, -1, null);
            } catch (Error e) {
                warning ("Failed to set power profile: %s",
                         e.message);
            }
        }

        public override Gtk.Widget ?create_submenu () {
            if (proxy == null) return null;

            var box = new Gtk.Box (
                Gtk.Orientation.VERTICAL, 0);
            box.add_css_class ("quick-settings-submenu");

            build_submenu_header (box);

            string current = proxy.active_profile;

            foreach (string name in profile_names) {
                var row = new Gtk.Box (
                    Gtk.Orientation.HORIZONTAL, 8);
                row.add_css_class ("submenu-row");

                var row_icon = new Gtk.Image.from_icon_name (
                    get_profile_icon (name));
                var row_label = new Gtk.Label (
                    get_profile_label (name));
                row_label.set_hexpand (true);
                row_label.set_halign (Gtk.Align.START);

                row.append (row_icon);
                row.append (row_label);

                if (name == current) {
                    var check = new Gtk.Image.from_icon_name (
                        "object-select-symbolic");
                    row.append (check);
                }

                var btn = new Gtk.Button ();
                btn.set_child (row);
                btn.add_css_class ("flat");

                string profile_name = name;
                btn.clicked.connect (() => {
                    set_profile.begin (profile_name);
                });

                box.append (btn);
            }

            return box;
        }
    }
}
