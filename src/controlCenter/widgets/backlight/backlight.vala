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
            string icon_name;
            string tooltip;
            bool is_internal;
        }

        BrightnessSource[] all_sources = {};

        [GtkChild]
        unowned Gtk.Box topbar;
        [GtkChild]
        unowned Gtk.Image topbar_icon;
        [GtkChild]
        unowned Gtk.Stack middle_stack;
        [GtkChild]
        unowned Gtk.Scale compact_scale;
        [GtkChild]
        unowned Gtk.ToggleButton reveal_btn;
        [GtkChild]
        unowned Gtk.Revealer revealer;
        [GtkChild]
        unowned Gtk.Box content;
        [GtkChild]
        unowned Gtk.Box single_source_box;

        int min_brightness = 0;
        OsdService? osd_proxy = null;

        private int primary_index = -1;
        private Gee.ArrayList<Gtk.Scale>[] source_scales;
        private bool[] source_updating_flags = {};

        public Backlight (string suffix) {
            base (suffix);

            Json.Object ?config = get_config (this);
            if (config != null) {
                int ?min_val = get_prop<int> (config, "min");
                if (min_val != null) {
                    min_brightness = int.max (0, min_val);
                }
            }

            try {
                osd_proxy = Bus.get_proxy_sync (BusType.SESSION,
                    "ru.ximperlinux.shell.OSD",
                    "/ru/ximperlinux/shell/OSD");
            } catch (Error e) {
                debug ("OSD service not available: %s", e.message);
            }

            detect_sources ();

            if (all_sources.length == 0) {
                hide ();
                return;
            }

            compact_scale.set_range (min_brightness, 100);

            build_ui ();
        }

        private void detect_sources () {
            BrightnessSource[] sysfs_displays = {};
            BrightnessSource[] ddc_displays = {};
            BrightnessSource[] kbd = {};

            // Scan /sys/class/backlight/ for display backlights (internal)
            try {
                var dir = Dir.open ("/sys/class/backlight");
                string ?name;
                while ((name = dir.read_name ()) != null) {
                    var util = new BacklightUtil ("backlight", name);
                    sysfs_displays += BrightnessSource () {
                        sysfs = util,
#if HAVE_DDC
                        ddc = null,
#endif
                        icon_name = "display-brightness-symbolic",
                        tooltip = name,
                        is_internal = true,
                    };
                }
            } catch (FileError e) {
                debug ("No /sys/class/backlight: %s", e.message);
            }

#if HAVE_DDC
            // Scan DDC displays (external)
            var ddc_list = DdcUtil.detect_displays ();
            for (int i = 0; i < ddc_list.length; i++) {
                var ddc = new DdcUtil (ddc_list[i].dispno);
                ddc_displays += BrightnessSource () {
                    sysfs = null,
                    ddc = ddc,
                    icon_name = "display-brightness-symbolic",
                    tooltip = ddc_list[i].display_name,
                    is_internal = false,
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
                    kbd += BrightnessSource () {
                        sysfs = util,
#if HAVE_DDC
                        ddc = null,
#endif
                        icon_name = "keyboard-brightness-symbolic",
                        tooltip = name,
                        is_internal = false,
                    };
                }
            } catch (FileError e) {
                debug ("No /sys/class/leds: %s", e.message);
            }

            // Order: internal first, then DDC displays, then keyboards
            foreach (var s in sysfs_displays) all_sources += s;
            foreach (var s in ddc_displays) all_sources += s;
            foreach (var s in kbd) all_sources += s;

            for (int i = 0; i < all_sources.length; i++) {
                if (all_sources[i].is_internal) {
                    primary_index = i;
                    break;
                }
            }
        }

        private string get_source_label (int index) {
            var src = all_sources[index];
            if (src.is_internal) {
                return _("Built-in Display");
            }
            if (src.icon_name
                    == "keyboard-brightness-symbolic") {
                return _("Keyboard");
            }
            return prettify_source_name (src.tooltip);
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
            if (hidden_count >= all_sources.length) {
                hide ();
            }
        }

        private void connect_source_scale (int index, Gtk.Scale scl) {
            bool first_scale =
                source_scales[index].size == 0;
            source_scales[index].add (scl);
            unowned BrightnessSource src = all_sources[index];
            int idx = index;

            if (src.sysfs != null) {
                unowned BacklightUtil util = src.sysfs;
                if (first_scale) {
                    util.brightness_change.connect ((percent) => {
                        update_scale_from_hw (idx, percent);
                    });
                }
                scl.value_changed.connect (() => {
                    if (source_updating_flags[idx]) return;
                    util.set_brightness.begin (
                        (float) scl.get_value ());
                    scl.tooltip_text =
                        ((int) scl.get_value ()).to_string ();
                    notify_osd (scl.get_value ());
                    sync_other_scales (idx, scl);
                });
            }
#if HAVE_DDC
            if (src.ddc != null) {
                unowned DdcUtil ddc = src.ddc;
                if (first_scale) {
                    ddc.brightness_change.connect ((percent) => {
                        update_scale_from_hw (idx, percent);
                    });
                }
                scl.value_changed.connect (() => {
                    if (source_updating_flags[idx]) return;
                    ddc.set_brightness.begin (
                        (float) scl.get_value ());
                    scl.tooltip_text =
                        ((int) scl.get_value ()).to_string ();
                    notify_osd (scl.get_value ());
                    sync_other_scales (idx, scl);
                });
            }
#endif
        }

        private void sync_other_scales (int index, Gtk.Scale changed) {
            source_updating_flags[index] = true;
            foreach (var scl in source_scales[index]) {
                if (scl != changed) {
                    scl.set_value (changed.get_value ());
                }
            }
            source_updating_flags[index] = false;
        }

        private void update_scale_from_hw (int index, double percent) {
            if (source_scales[index].size == 0) return;
            if (percent < 0) {
                foreach (var scl in source_scales[index]) {
                    scl.set_visible (false);
                }
                source_hidden ();
                return;
            }
            source_updating_flags[index] = true;
            foreach (var scl in source_scales[index]) {
                scl.set_value (percent);
            }
            source_updating_flags[index] = false;
        }

        [GtkCallback]
        private void on_reveal_toggled () {
            bool expanded = reveal_btn.active;
            revealer.set_reveal_child (expanded);

            if (expanded) {
                reveal_btn.set_icon_name (
                    "ximper-shell-notification-center-down-small-symbolic");
                add_css_class ("submenu");
            } else {
                reveal_btn.set_icon_name (
                    "ximper-shell-notification-center-up-small-symbolic");
                remove_css_class ("submenu");
            }

            // Switch topbar middle: slider in compact mode, label when expanded
            if (primary_index >= 0) {
                middle_stack.set_visible_child_name (
                    expanded ? "header" : "slider");
            }

            // Apply accent header icon style when expanded
            if (expanded) {
                topbar_icon.add_css_class (
                    "submenu-header-icon");
            } else {
                topbar_icon.remove_css_class (
                    "submenu-header-icon");
            }
        }

        private Gtk.Box build_source_row (int index) {
            var outer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            var name_label = new Gtk.Label (
                get_source_label (index));
            name_label.set_halign (Gtk.Align.START);
            name_label.add_css_class ("dim-label");
            name_label.add_css_class ("caption");
            outer.append (name_label);

            var scl = new Gtk.Scale.with_range (
                Gtk.Orientation.HORIZONTAL,
                min_brightness, 100, 1);
            scl.set_draw_value (false);
            scl.set_round_digits (0);
            scl.set_hexpand (true);
            outer.append (scl);

            connect_source_scale (index, scl);

            return outer;
        }

        private void build_ui () {
            source_scales =
                new Gee.ArrayList<Gtk.Scale>[all_sources.length];
            for (int i = 0; i < all_sources.length; i++) {
                source_scales[i] =
                    new Gee.ArrayList<Gtk.Scale> ();
            }
            source_updating_flags = new bool[all_sources.length];

            // Case A: exactly one source — simple single slider, no toggle
            if (all_sources.length == 1) {
                topbar.set_visible (false);
                revealer.set_visible (false);
                single_source_box.set_visible (true);

                var row = new Gtk.Box (
                    Gtk.Orientation.HORIZONTAL, 0);
                var icon = new Gtk.Image.from_icon_name (
                    all_sources[0].icon_name);
                icon.set_tooltip_text (all_sources[0].tooltip);
                var scl = new Gtk.Scale.with_range (
                    Gtk.Orientation.HORIZONTAL,
                    min_brightness, 100, 1);
                scl.set_draw_value (false);
                scl.set_round_digits (0);
                scl.set_hexpand (true);
                row.append (icon);
                row.append (scl);
                single_source_box.append (row);

                connect_source_scale (0, scl);
                return;
            }

            add_css_class ("has-collapse");
            single_source_box.set_visible (false);

            if (primary_index >= 0) {
                // Internal display exists — compact slider shown by default
                connect_source_scale (primary_index, compact_scale);
                middle_stack.set_visible_child_name ("slider");
            } else {
                // No internal — always show header, no compact slider
                middle_stack.set_visible_child_name ("header");
                topbar_icon.add_css_class (
                    "submenu-header-icon");
            }

            bool last_was_display = false;
            for (int i = 0; i < all_sources.length; i++) {
                bool is_kbd = all_sources[i].icon_name
                    == "keyboard-brightness-symbolic";
                if (is_kbd && last_was_display) {
                    content.append (new Gtk.Separator (
                        Gtk.Orientation.HORIZONTAL));
                }
                content.append (build_source_row_dual (i));
                last_was_display = !is_kbd;
            }
        }

        private Gtk.Box build_source_row_dual (int index) {
            var outer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            var header = new Gtk.Box (
                Gtk.Orientation.HORIZONTAL, 6);
            var icon = new Gtk.Image.from_icon_name (
                all_sources[index].icon_name);
            var name_label = new Gtk.Label (
                get_source_label (index));
            name_label.set_halign (Gtk.Align.START);
            name_label.set_ellipsize (
                Pango.EllipsizeMode.END);
            name_label.add_css_class ("dim-label");
            name_label.add_css_class ("caption");
            header.append (icon);
            header.append (name_label);
            outer.append (header);

            unowned BrightnessSource src = all_sources[index];
            bool is_kbd = src.icon_name
                == "keyboard-brightness-symbolic";
            int max = src.sysfs != null
                ? src.sysfs.get_max_value () : 100;
            double step = is_kbd && max > 0 && max <= 20
                ? 100.0 / max : 1.0;

            var scl = new Gtk.Scale.with_range (
                Gtk.Orientation.HORIZONTAL,
                min_brightness, 100, step);
            scl.set_draw_value (false);
            scl.set_round_digits (0);
            scl.set_hexpand (true);

            if (is_kbd && max > 0 && max <= 20) {
                for (int i = 0; i <= max; i++) {
                    scl.add_mark (
                        i * 100.0 / max,
                        Gtk.PositionType.BOTTOM, null);
                }
                int snap_max = max;
                bool snapping = false;
                scl.value_changed.connect (() => {
                    if (snapping) return;
                    double v = scl.get_value ();
                    double snapped =
                        Math.round (v * snap_max / 100.0)
                        * 100.0 / snap_max;
                    if (v != snapped) {
                        snapping = true;
                        scl.set_value (snapped);
                        snapping = false;
                    }
                });
            }

            outer.append (scl);

            connect_source_scale (index, scl);

            return outer;
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
            for (int i = 0; i < all_sources.length; i++) {
                if (all_sources[i].sysfs != null) {
                    if (val) {
                        all_sources[i].sysfs.start ();
                    } else {
                        all_sources[i].sysfs.close ();
                    }
                }
#if HAVE_DDC
                if (all_sources[i].ddc != null) {
                    if (val) {
                        all_sources[i].ddc.start ();
                    } else {
                        all_sources[i].ddc.close ();
                    }
                }
#endif
            }

            if (val) {
                reveal_btn.set_active (false);
            }
        }
    }
}
