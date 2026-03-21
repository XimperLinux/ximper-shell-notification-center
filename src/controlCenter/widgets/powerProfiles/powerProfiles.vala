namespace XimperShellNotificationCenter.Widgets {
    [DBus (name = "net.hadess.PowerProfiles")]
    interface PowerProfilesProxy : Object {
        public abstract string active_profile { owned get; set; }
        public abstract HashTable<string, Variant>[] profiles { owned get; }
    }

    public class PowerProfiles : Object {
        PowerProfilesProxy? proxy = null;
        DBusProxy raw_proxy = null;

        Gtk.ToggleButton show_button;
        Gtk.Revealer revealer;
        Gtk.Box menu;

        string[] profile_names = {};
        Gtk.ToggleButton[] profile_buttons = {};
        bool updating_buttons = false;

        // Custom label overrides from config (profile_name -> full button text)
        HashTable<string, string> label_overrides;

        public signal void request_close_other_revealers ();

        public PowerProfiles (string label,
                              int animation_duration,
                              Gtk.RevealerTransitionType animation_type,
                              HashTable<string, string>? label_overrides) {
            this.label_overrides = label_overrides ?? new HashTable<string, string> (str_hash, str_equal);

            show_button = new Gtk.ToggleButton.with_label (label);

            menu = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            menu.add_css_class ("power-profiles");

            revealer = new Gtk.Revealer () {
                child = menu,
                transition_duration = animation_duration,
                transition_type = animation_type,
            };

            revealer.bind_property ("child-revealed",
                                    show_button, "active",
                                    BindingFlags.SYNC_CREATE, null, null);

            show_button.clicked.connect (() => {
                bool visible = !revealer.get_reveal_child ();
                request_close_other_revealers ();
                revealer.set_reveal_child (visible);
            });

            connect_dbus.begin ();
        }

        private async void connect_dbus () {
            try {
                proxy = yield Bus.get_proxy (BusType.SYSTEM,
                                             "net.hadess.PowerProfiles",
                                             "/net/hadess/PowerProfiles");
                raw_proxy = proxy as DBusProxy;
                populate_profiles ();
                raw_proxy.g_properties_changed.connect (on_properties_changed);
            } catch (Error e) {
                warning ("PowerProfiles D-Bus not available: %s", e.message);
                show_button.set_visible (false);
                revealer.set_visible (false);
            }
        }

        private void on_properties_changed (Variant changed, string[] invalidated) {
            var iter = changed.iterator ();
            string key;
            Variant val;
            while (iter.next ("{sv}", out key, out val)) {
                if (key == "ActiveProfile") {
                    update_active_button (val.get_string ());
                } else if (key == "Profiles") {
                    populate_profiles ();
                }
            }
        }

        private async void set_profile (string profile_name) {
            if (raw_proxy == null) return;
            try {
                yield raw_proxy.call (
                    "org.freedesktop.DBus.Properties.Set",
                    new Variant ("(ssv)",
                                 "net.hadess.PowerProfiles",
                                 "ActiveProfile",
                                 new Variant.string (profile_name)),
                    DBusCallFlags.NONE, -1, null);
            } catch (Error e) {
                warning ("Failed to set power profile: %s", e.message);
            }
        }

        private void populate_profiles () {
            if (proxy == null) return;

            Gtk.Widget? child = menu.get_first_child ();
            while (child != null) {
                Gtk.Widget? next = child.get_next_sibling ();
                menu.remove (child);
                child = next;
            }
            profile_names = {};
            profile_buttons = {};

            string active = proxy.active_profile;

            foreach (var profile in proxy.profiles) {
                Variant? v = profile.lookup ("Profile");
                if (v == null) continue;
                string name = v.get_string ();

                // Use override if set, otherwise default
                string? custom = label_overrides.lookup (name);
                string display = custom ?? get_default_label (name);

                var btn = new Gtk.ToggleButton ();
                btn.set_hexpand (true);
                btn.set_label (display);
                btn.set_active (name == active);

                string profile_name = name;
                btn.toggled.connect (() => {
                    if (!updating_buttons && btn.active) {
                        set_profile.begin (profile_name);
                    }
                });

                menu.append (btn);
                profile_names += name;
                profile_buttons += btn;
            }
        }

        private void update_active_button (string active_profile) {
            updating_buttons = true;
            for (int i = 0; i < profile_names.length; i++) {
                profile_buttons[i].set_active (profile_names[i] == active_profile);
            }
            updating_buttons = false;
        }

        private string get_default_label (string profile) {
            switch (profile) {
                case "performance":  return "\xf0\x9f\x9a\x80 Performance";
                case "balanced":     return "\xe2\x9a\x96 Balanced";
                case "power-saver":  return "\xf0\x9f\x94\x8b Power Saver";
                default:             return profile;
            }
        }

        public Gtk.ToggleButton get_button () { return show_button; }
        public Gtk.Revealer get_revealer () { return revealer; }
        public void close () { revealer.set_reveal_child (false); }
    }
}
