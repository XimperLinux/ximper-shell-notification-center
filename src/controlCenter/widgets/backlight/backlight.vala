using GLib;

namespace XimperShellNotificationCenter.Widgets {
    public class Backlight : BaseWidget {
        public override string widget_name {
            get {
                return "backlight";
            }
        }

        BacklightUtil client;
#if HAVE_DDC
        DdcUtil[] ddc_clients = {};
        bool use_ddc = false;
#endif

        Gtk.Image icon_widget = new Gtk.Image.from_icon_name (
            "display-brightness-symbolic");
        Gtk.Scale slider = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 100, 1);

        public Backlight (string suffix) {
            base (suffix);

            Json.Object ?config = get_config (this);
            if (config != null) {
                string device = (get_prop<string> (config, "device") ?? "intel_backlight");
                string subsystem = (get_prop<string> (config, "subsystem") ?? "backlight");
                int min = int.max (0, get_prop<int> (config, "min"));

                switch (subsystem) {
                    default :
                        info ("Invalid subsystem %s for device %s. " +
                              "Use 'backlight', 'leds'" +
#if HAVE_DDC
                              ", 'ddc'" +
#endif
                              ". Using default: 'backlight'",
                              subsystem, device);
                        client = new BacklightUtil ("backlight", device);
                        break;
                    case "backlight":
                        client = new BacklightUtil ("backlight", device);
                        slider.set_range (min, 100);
                        break;
                    case "leds":
                        client = new BacklightUtil ("leds", device);
                        slider.set_range (min, this.client.get_max_value ());
                        break;
#if HAVE_DDC
                    case "ddc":
                        int display_number = int.max (0, get_prop<int> (config, "display-number"));
                        use_ddc = true;

                        if (display_number > 0) {
                            ddc_clients += new DdcUtil (display_number);
                            slider.set_range (min, 100);
                        } else {
                            // Auto-detect all DDC displays
                            var displays = DdcUtil.detect_displays ();
                            if (displays.length == 0) {
                                warning ("No DDC displays found");
                                hide ();
                                return;
                            }
                            for (int i = 0; i < displays.length; i++) {
                                var ddc = new DdcUtil (displays[i].dispno);
                                ddc_clients += ddc;
                            }
                        }
                        break;
#endif
                }
            }

#if HAVE_DDC
            if (use_ddc) {
                if (ddc_clients.length == 1) {
                    // Single DDC display — use the existing icon + slider
                    icon_widget.set_tooltip_text (
                        ddc_clients[0].get_display_name ());
                    ddc_clients[0].brightness_change.connect ((percent) => {
                        if (percent < 0) {
                            hide ();
                        } else {
                            slider.set_value (percent);
                        }
                    });
                    slider.set_draw_value (false);
                    slider.set_round_digits (0);
                    slider.set_hexpand (true);
                    slider.value_changed.connect (() => {
                        ddc_clients[0].set_brightness.begin ((float) slider.get_value ());
                        slider.tooltip_text = ((int) slider.get_value ()).to_string ();
                    });
                    append (icon_widget);
                    append (slider);
                } else {
                    // Multiple DDC displays — create a row per display
                    set_orientation (Gtk.Orientation.VERTICAL);
                    var size_group = new Gtk.SizeGroup (
                        Gtk.SizeGroupMode.HORIZONTAL);
                    for (int i = 0; i < ddc_clients.length; i++) {
                        var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                        var label_box = new Gtk.Box (
                            Gtk.Orientation.HORIZONTAL, 6);
                        label_box.set_halign (Gtk.Align.CENTER);
                        size_group.add_widget (label_box);
                        var icon = new Gtk.Image.from_icon_name (
                            "display-brightness-symbolic");
                        var num_label = new Gtk.Label (
                            (i + 1).to_string ());
                        icon.set_tooltip_text (
                            ddc_clients[i].get_display_name ());
                        label_box.append (icon);
                        label_box.append (num_label);
                        var scl = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 100, 1);
                        scl.set_draw_value (false);
                        scl.set_round_digits (0);
                        scl.set_hexpand (true);

                        int idx = i;
                        ddc_clients[i].brightness_change.connect ((percent) => {
                            if (percent < 0) {
                                row.set_visible (false);
                            } else {
                                scl.set_value (percent);
                            }
                        });
                        scl.value_changed.connect (() => {
                            ddc_clients[idx].set_brightness.begin ((float) scl.get_value ());
                            scl.tooltip_text = ((int) scl.get_value ()).to_string ();
                        });

                        row.append (label_box);
                        row.append (scl);
                        append (row);
                    }
                }
                return;
            }
#endif

            this.client.brightness_change.connect ((percent) => {
                if (percent < 0) { // invalid device path
                    hide ();
                } else {
                    slider.set_value (percent);
                }
            });

            slider.set_draw_value (false);
            slider.set_round_digits (0);
            slider.set_hexpand (true);
            slider.value_changed.connect (() => {
                this.client.set_brightness.begin ((float) slider.get_value ());
                slider.tooltip_text = ((int) slider.get_value ()).to_string ();
            });

            append (icon_widget);
            append (slider);
        }

        public override void on_cc_visibility_change (bool val) {
#if HAVE_DDC
            if (use_ddc) {
                foreach (var ddc in ddc_clients) {
                    if (val) {
                        ddc.start ();
                    } else {
                        ddc.close ();
                    }
                }
                return;
            }
#endif
            if (val) {
                this.client.start ();
            } else {
                this.client.close ();
            }
        }
    }
}
