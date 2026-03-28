using GLib;

namespace XimperShellNotificationCenter.Widgets {

    [DBus (name = "ru.ximperlinux.shell.OSD")]
    interface OsdService : Object {
        public abstract void show_brightness_osd (double percent) throws DBusError, IOError;
    }

    [GtkTemplate (ui = "/ru/ximperlinux/shell/NotificationCenter/ui/widgets/backlight.ui")]
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

        [GtkChild]
        unowned Gtk.Box topbar;
        [GtkChild]
        unowned Gtk.ToggleButton reveal_btn;
        [GtkChild]
        unowned Gtk.Revealer revealer;
        [GtkChild]
        unowned Gtk.Box displays_box;
        [GtkChild]
        unowned Gtk.Separator separator;
        [GtkChild]
        unowned Gtk.Box kbd_box;
        [GtkChild]
        unowned Gtk.Box single_source_box;

        int min_brightness = 0;
        OsdService? osd_proxy = null;

        public Backlight (string suffix) {
            base (suffix);

            Json.Object ?config = get_config (this);
            if (config != null) {
                min_brightness = int.max (0, get_prop<int> (config, "min"));
            }

            try {
                osd_proxy = Bus.get_proxy_sync (BusType.SESSION,
                    "ru.ximperlinux.shell.OSD",
                    "/ru/ximperlinux/shell/OSD");
            } catch (Error e) {
                debug ("OSD service not available: %s", e.message);
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
                    notify_osd (scl.get_value ());
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
                    notify_osd (scl.get_value ());
                });
            }
#endif

            return outer;
        }

        [GtkCallback]
        private void on_reveal_toggled () {
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
        }

        private void build_ui () {
            bool need_collapse = display_sources.length > 1
                                 || kbd_sources.length > 0;

            if (!need_collapse && display_sources.length == 1) {
                // Single display — simple row, hide multi-source UI
                topbar.set_visible (false);
                revealer.set_visible (false);
                single_source_box.set_visible (true);
                var row = create_slider_row (
                    ref display_sources[0], null, false);
                single_source_box.append (row);
                return;
            }

            // Multiple sources — collapsible layout
            if (need_collapse) {
                single_source_box.set_visible (false);
                add_css_class ("has-collapse");

                // Display sources
                if (display_sources.length > 0) {
                    var sg = new Gtk.SizeGroup (
                        Gtk.SizeGroupMode.HORIZONTAL);
                    for (int i = 0; i < display_sources.length; i++) {
                        var row = create_slider_row (
                            ref display_sources[i], sg, true);
                        displays_box.append (row);
                    }
                } else {
                    displays_box.set_visible (false);
                }

                // Separator
                separator.set_visible (
                    display_sources.length > 0
                    && kbd_sources.length > 0);

                // Keyboard sources
                if (kbd_sources.length > 0) {
                    var sg = new Gtk.SizeGroup (
                        Gtk.SizeGroupMode.HORIZONTAL);
                    for (int i = 0; i < kbd_sources.length; i++) {
                        var row = create_slider_row (
                            ref kbd_sources[i], sg, true);
                        kbd_box.append (row);
                    }
                } else {
                    kbd_box.set_visible (false);
                }
            }
        }

        private void notify_osd (double percent) {
            if (osd_proxy == null) return;
            try {
                osd_proxy.show_brightness_osd (percent);
            } catch (Error e) {
                debug ("OSD call failed: %s", e.message);
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

            if (val) {
                reveal_btn.set_active (false);
            }
        }
    }
}
