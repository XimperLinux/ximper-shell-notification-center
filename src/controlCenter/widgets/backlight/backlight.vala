using GLib;

namespace XimperShellNotificationCenter.Widgets {
    public class Backlight : BaseWidget {
        public override string widget_name {
            get {
                return "backlight";
            }
        }

        private struct BrightnessSource {
            BacklightUtil ?sysfs;
#if HAVE_DDC
            DdcUtil ?ddc;
#endif
            Gtk.Box row;
            Gtk.Scale scale;
            string icon_name;
            string tooltip;
        }

        BrightnessSource[] display_sources = {};
        BrightnessSource[] kbd_sources = {};

        Gtk.Box ?displays_box = null;
        Gtk.Box ?kbd_box = null;
        Gtk.Separator ?separator = null;
        Gtk.Revealer ?revealer = null;
        Gtk.ToggleButton ?reveal_btn = null;

        int min_brightness = 0;

        public Backlight (string suffix) {
            base (suffix);
            set_orientation (Gtk.Orientation.VERTICAL);

            Json.Object ?config = get_config (this);
            if (config != null) {
                min_brightness = int.max (0, get_prop<int> (config, "min"));
            }

            detect_sources ();

            int total = display_sources.length + kbd_sources.length;
            if (total == 0) {
                hide ();
                return;
            }

            build_ui ();
        }

        private void detect_sources () {
            // Scan /sys/class/backlight/ for display backlights
            try {
                var dir = Dir.open ("/sys/class/backlight");
                string ?name;
                while ((name = dir.read_name ()) != null) {
                    var util = new BacklightUtil ("backlight", name);
                    display_sources += BrightnessSource () {
                        sysfs = util,
#if HAVE_DDC
                        ddc = null,
#endif
                        icon_name = "display-brightness-symbolic",
                        tooltip = name,
                    };
                }
            } catch (FileError e) {
                debug ("No /sys/class/backlight: %s", e.message);
            }

#if HAVE_DDC
            // Scan DDC displays
            var ddc_displays = DdcUtil.detect_displays ();
            for (int i = 0; i < ddc_displays.length; i++) {
                var ddc = new DdcUtil (ddc_displays[i].dispno);
                display_sources += BrightnessSource () {
                    sysfs = null,
                    ddc = ddc,
                    icon_name = "display-brightness-symbolic",
                    tooltip = ddc_displays[i].display_name,
                };
            }
#endif

            // Scan /sys/class/leds/ for keyboard backlights
            try {
                var dir = Dir.open ("/sys/class/leds");
                string ?name;
                while ((name = dir.read_name ()) != null) {
                    if (!name.contains ("kbd")) {
                        continue;
                    }
                    var util = new BacklightUtil ("leds", name);
                    kbd_sources += BrightnessSource () {
                        sysfs = util,
#if HAVE_DDC
                        ddc = null,
#endif
                        icon_name = "keyboard-brightness-symbolic",
                        tooltip = name,
                    };
                }
            } catch (FileError e) {
                debug ("No /sys/class/leds: %s", e.message);
            }
        }

        private static string prettify_source_name (string name) {
            // DDC names are already nice (e.g. "DELL U2723QE")
            // Sysfs backlight: "amdgpu_bl1" → "AMDGPU BL1"
            // Kbd: "asus::kbd_backlight" → "Asus Keyboard"
            string result = name;

            // Keyboard backlight cleanup
            if (result.contains ("kbd")) {
                result = result.replace ("_backlight", "");
                result = result.replace ("::kbd", "");
                result = result.replace ("::", " ");
                if (result.strip ().length > 0) {
                    string first = result.substring (0, 1).up ();
                    result = first + result.substring (1);
                }
                return result.strip ();
            }

            // Sysfs backlight: replace _ with space, uppercase
            result = result.replace ("_", " ").up ();
            return result;
        }

        private int hidden_count = 0;

        private void source_hidden () {
            hidden_count++;
            int total = display_sources.length + kbd_sources.length;
            if (hidden_count >= total) {
                hide ();
            }
        }

        private Gtk.Box create_slider_row (ref BrightnessSource src,
                                           Gtk.SizeGroup ?sg,
                                           bool show_label) {
            var outer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            if (show_label) {
                var name_label = new Gtk.Label (
                    prettify_source_name (src.tooltip));
                name_label.set_halign (Gtk.Align.START);
                name_label.add_css_class ("dim-label");
                name_label.add_css_class ("caption");
                outer.append (name_label);
            }

            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            var scl = new Gtk.Scale.with_range (
                Gtk.Orientation.HORIZONTAL, min_brightness, 100, 1);
            scl.set_draw_value (false);
            scl.set_round_digits (0);
            scl.set_hexpand (true);

            var icon = new Gtk.Image.from_icon_name (src.icon_name);
            icon.set_tooltip_text (src.tooltip);

            if (sg != null) {
                var label_box = new Gtk.Box (
                    Gtk.Orientation.HORIZONTAL, 6);
                label_box.set_halign (Gtk.Align.CENTER);
                sg.add_widget (label_box);
                label_box.append (icon);
                row.append (label_box);
            } else {
                row.append (icon);
            }

            row.append (scl);
            outer.append (row);

            src.row = outer;
            src.scale = scl;

            // Connect signals
            if (src.sysfs != null) {
                unowned BacklightUtil util = src.sysfs;
                util.brightness_change.connect ((percent) => {
                    if (percent < 0) {
                        outer.set_visible (false);
                        source_hidden ();
                    } else {
                        scl.set_value (percent);
                    }
                });
                scl.value_changed.connect (() => {
                    util.set_brightness.begin (
                        (float) scl.get_value ());
                    scl.tooltip_text =
                        ((int) scl.get_value ()).to_string ();
                });
            }
#if HAVE_DDC
            if (src.ddc != null) {
                unowned DdcUtil ddc = src.ddc;
                ddc.brightness_change.connect ((percent) => {
                    if (percent < 0) {
                        outer.set_visible (false);
                        source_hidden ();
                    } else {
                        scl.set_value (percent);
                    }
                });
                scl.value_changed.connect (() => {
                    ddc.set_brightness.begin (
                        (float) scl.get_value ());
                    scl.tooltip_text =
                        ((int) scl.get_value ()).to_string ();
                });
            }
#endif

            return outer;
        }

        private void build_ui () {
            bool need_collapse = display_sources.length > 1
                                 || kbd_sources.length > 0;

            if (!need_collapse && display_sources.length == 1) {
                // Single display — simple row
                var row = create_slider_row (
                    ref display_sources[0], null, false);
                append (row);
                return;
            }

            // Multiple sources — collapsible layout
            if (need_collapse) {
                add_css_class ("has-collapse");
                var topbar = new Gtk.Box (
                    Gtk.Orientation.HORIZONTAL, 6);
                var topbar_icon = new Gtk.Image.from_icon_name (
                    "display-brightness-symbolic");
                var topbar_label = new Gtk.Label (
                    _("Brightness"));
                topbar_label.set_hexpand (true);
                topbar_label.set_halign (Gtk.Align.START);
                reveal_btn = new Gtk.ToggleButton ();
                reveal_btn.set_icon_name (
                    "ximper-shell-notification-center-up-small-symbolic");
                topbar.append (topbar_icon);
                topbar.append (topbar_label);
                topbar.append (reveal_btn);
                append (topbar);

                revealer = new Gtk.Revealer ();
                revealer.set_transition_type (
                    Gtk.RevealerTransitionType.SLIDE_DOWN);
                revealer.set_transition_duration (200);

                var content = new Gtk.Box (
                    Gtk.Orientation.VERTICAL, 0);
                revealer.set_child (content);
                append (revealer);

                reveal_btn.toggled.connect (() => {
                    revealer.set_reveal_child (reveal_btn.active);
                    if (reveal_btn.active) {
                        reveal_btn.set_icon_name (
                            "ximper-shell-notification-center-down-small-symbolic");
                        add_css_class ("expanded");
                    } else {
                        reveal_btn.set_icon_name (
                            "ximper-shell-notification-center-up-small-symbolic");
                        remove_css_class ("expanded");
                    }
                });

                // Display sources
                if (display_sources.length > 0) {
                    displays_box = new Gtk.Box (
                        Gtk.Orientation.VERTICAL, 0);
                    var sg = new Gtk.SizeGroup (
                        Gtk.SizeGroupMode.HORIZONTAL);
                    for (int i = 0; i < display_sources.length; i++) {
                        var row = create_slider_row (
                            ref display_sources[i], sg, true);
                        displays_box.append (row);
                    }
                    content.append (displays_box);
                }

                // Separator
                if (display_sources.length > 0
                    && kbd_sources.length > 0) {
                    separator = new Gtk.Separator (
                        Gtk.Orientation.HORIZONTAL);
                    separator.set_margin_top (8);
                    separator.set_margin_bottom (8);
                    content.append (separator);
                }

                // Keyboard sources
                if (kbd_sources.length > 0) {
                    kbd_box = new Gtk.Box (
                        Gtk.Orientation.VERTICAL, 0);
                    var sg = new Gtk.SizeGroup (
                        Gtk.SizeGroupMode.HORIZONTAL);
                    for (int i = 0; i < kbd_sources.length; i++) {
                        var row = create_slider_row (
                            ref kbd_sources[i], sg, true);
                        kbd_box.append (row);
                    }
                    content.append (kbd_box);
                }
            }
        }

        public override void on_cc_visibility_change (bool val) {
            for (int i = 0; i < display_sources.length; i++) {
                if (display_sources[i].sysfs != null) {
                    if (val) {
                        display_sources[i].sysfs.start ();
                    } else {
                        display_sources[i].sysfs.close ();
                    }
                }
#if HAVE_DDC
                if (display_sources[i].ddc != null) {
                    if (val) {
                        display_sources[i].ddc.start ();
                    } else {
                        display_sources[i].ddc.close ();
                    }
                }
#endif
            }
            for (int i = 0; i < kbd_sources.length; i++) {
                if (kbd_sources[i].sysfs != null) {
                    if (val) {
                        kbd_sources[i].sysfs.start ();
                    } else {
                        kbd_sources[i].sysfs.close ();
                    }
                }
            }

            if (val && reveal_btn != null) {
                reveal_btn.set_active (false);
            }
        }
    }
}
