namespace XimperShellNotificationCenter.Widgets {
    public class Volume : BaseWidget {
        public override string widget_name {
            get {
                return "volume";
            }
        }

        Gtk.Box main_volume_slider_container = new Gtk.Box (
            Gtk.Orientation.HORIZONTAL, 0);
        Gtk.Image icon_widget = new Gtk.Image ();
        Gtk.Scale slider = new Gtk.Scale.with_range (
            Gtk.Orientation.HORIZONTAL, 0, 100, 1);

        // Expandable section
        Gtk.ToggleButton reveal_button;
        Gtk.Revealer revealer;
        Gtk.Box revealer_content;

        // Per app volume
        Gtk.ListBox levels_listbox;
        IterListBoxController list_box_controller;

        // Sink selector
        Gtk.Separator sink_separator;
        Gtk.Box sink_list_box;
        uint sink_rebuild_timeout = 0;

        private PulseDevice ?default_sink = null;
        private PulseDaemon client = new PulseDaemon ();

        construct {
            this.client.change_default_device.connect (
                default_device_changed);

            icon_widget.set_from_icon_name (
                "audio-volume-high-symbolic");

            slider.value_changed.connect (() => {
                if (default_sink != null) {
                    this.client.set_device_volume (
                        default_sink,
                        (float) slider.get_value ());
                    slider.tooltip_text =
                        ((int) slider.get_value ()).to_string ();
                }
                update_volume_icon ((int) slider.get_value ());
            });
        }

        public Volume (string suffix) {
            base (suffix);

            this.orientation = Gtk.Orientation.VERTICAL;

            // Main slider
            slider.draw_value = false;
            slider.set_hexpand (true);
            main_volume_slider_container.append (icon_widget);
            main_volume_slider_container.append (slider);

            // Reveal button
            reveal_button = new Gtk.ToggleButton ();
            set_button_icon ();
            reveal_button.toggled.connect (() => {
                set_button_icon ();
                revealer.set_reveal_child (reveal_button.active);
                if (reveal_button.active) {
                    add_css_class ("expanded");
                } else {
                    remove_css_class ("expanded");
                }
            });
            main_volume_slider_container.append (reveal_button);
            append (main_volume_slider_container);

            // Revealer with per-app + sink selector
            revealer = new Gtk.Revealer ();
            revealer.transition_type =
                Gtk.RevealerTransitionType.SLIDE_DOWN;
            revealer.transition_duration = 200;

            revealer_content = new Gtk.Box (
                Gtk.Orientation.VERTICAL, 0);
            revealer.set_child (revealer_content);

            // Per-app volume list
            levels_listbox = new Gtk.ListBox ();
            levels_listbox.add_css_class ("per-app-volume");
            levels_listbox.set_activate_on_single_click (true);
            levels_listbox.set_selection_mode (
                Gtk.SelectionMode.NONE);
            list_box_controller = new IterListBoxController (
                levels_listbox);

            foreach (var item in this.client.active_sinks.values) {
                SinkInputRow row = new SinkInputRow (
                    item, client);
                list_box_controller.append (row);
            }

            this.client.change_active_sink.connect (
                active_sink_change);
            this.client.new_active_sink.connect (
                active_sink_added);
            this.client.remove_active_sink.connect (
                active_sink_removed);

            revealer_content.append (levels_listbox);

            // Separator between per-app and sinks
            sink_separator = new Gtk.Separator (
                Gtk.Orientation.HORIZONTAL);
            sink_separator.set_margin_top (8);
            sink_separator.set_margin_bottom (8);
            sink_separator.set_visible (false);
            revealer_content.append (sink_separator);

            // Sink selector
            sink_list_box = new Gtk.Box (
                Gtk.Orientation.VERTICAL, 0);
            sink_list_box.add_css_class ("sink-selector");
            sink_list_box.set_margin_start (4);
            sink_list_box.set_margin_end (4);
            sink_list_box.set_margin_top (4);
            sink_list_box.set_margin_bottom (4);
            sink_list_box.set_visible (false);
            revealer_content.append (sink_list_box);

            append (revealer);

            // Device signals
            this.client.new_device.connect (on_device_changed);
            this.client.change_device.connect (
                on_device_changed);
            this.client.remove_device.connect (
                on_device_changed);

            update_reveal_visibility ();
        }

        private void update_volume_icon (int volume) {
            string icon_name;
            if (volume <= 0) {
                icon_name = "audio-volume-muted-symbolic";
            } else if (volume <= 33) {
                icon_name = "audio-volume-low-symbolic";
            } else if (volume <= 66) {
                icon_name = "audio-volume-medium-symbolic";
            } else {
                icon_name = "audio-volume-high-symbolic";
            }
            icon_widget.set_from_icon_name (icon_name);
        }

        private void set_button_icon () {
            if (!reveal_button.active) {
                reveal_button.set_icon_name (
                    "ximper-shell-notification-center-up-small-symbolic");
            } else {
                reveal_button.set_icon_name (
                    "ximper-shell-notification-center-down-small-symbolic");
            }
        }

        private void update_reveal_visibility () {
            bool has_apps = client.active_sinks.size > 0;
            bool has_sinks = count_output_sinks () > 1;

            // Show/hide components
            levels_listbox.set_visible (has_apps);
            sink_separator.set_visible (has_apps && has_sinks);

            // Show reveal button only if there's something
            reveal_button.set_visible (has_apps || has_sinks);
        }

        private int count_output_sinks () {
            int count = 0;
            foreach (var device in client.sinks.values) {
                if (device.removed) continue;
                if (device.direction
                    != PulseAudio.Direction.OUTPUT) {
                    continue;
                }
                count++;
            }
            return count;
        }

        public override void on_cc_visibility_change (bool val) {
            if (val) {
                this.client.start ();
            } else {
                this.client.close ();
                reveal_button.set_active (false);
            }
        }

        private void default_device_changed (PulseDevice device) {
            if (device != null
                && device.direction
                    == PulseAudio.Direction.OUTPUT) {
                this.default_sink = device;
                slider.set_value (device.volume);
            }
        }

        private void active_sink_change (PulseSinkInput sink) {
            foreach (unowned Gtk.Widget row
                     in list_box_controller.get_children ()) {
                if (!(row is SinkInputRow)) continue;
                var s = (SinkInputRow) row;
                if (s.sink_input.cmp (sink)) {
                    s.update (sink);
                    break;
                }
            }
        }

        private void active_sink_added (PulseSinkInput sink) {
            SinkInputRow row = new SinkInputRow (
                sink, client);
            list_box_controller.append (row);
            update_reveal_visibility ();
        }

        private void active_sink_removed (PulseSinkInput sink) {
            foreach (unowned Gtk.Widget row
                     in list_box_controller.get_children ()) {
                if (!(row is SinkInputRow)) continue;
                var s = (SinkInputRow) row;
                if (s.sink_input.cmp (sink)) {
                    list_box_controller.remove (row);
                    break;
                }
            }
            update_reveal_visibility ();
        }

        private static string get_sink_icon (string ?name) {
            if (name == null || name.length == 0) {
                return "audio-card-symbolic";
            }
            var theme = Gtk.IconTheme.get_for_display (
                Gdk.Display.get_default ());

            string[] candidates = { name, name + "-symbolic" };

            string shortened = name;
            while (shortened.last_index_of ("-") > 0) {
                shortened = shortened.substring (
                    0, shortened.last_index_of ("-"));
                candidates += shortened;
                candidates += shortened + "-symbolic";
            }

            foreach (string candidate in candidates) {
                if (theme.has_icon (candidate)) {
                    return candidate;
                }
            }
            return "audio-card-symbolic";
        }

        private void on_device_changed (PulseDevice device) {
            if (sink_rebuild_timeout != 0) {
                Source.remove (sink_rebuild_timeout);
            }
            sink_rebuild_timeout = Timeout.add (100, () => {
                sink_rebuild_timeout = 0;
                rebuild_sink_list ();
                return Source.REMOVE;
            });
        }

        private void rebuild_sink_list () {
            // Clear existing
            for (var child = sink_list_box.get_first_child ();
                 child != null;) {
                var next = child.get_next_sibling ();
                sink_list_box.remove (child);
                child = next;
            }

            // Collect OUTPUT sinks
            int count = 0;
            foreach (var device in client.sinks.values) {
                if (device.removed) continue;
                if (device.direction
                    != PulseAudio.Direction.OUTPUT) {
                    continue;
                }

                count++;
                var row = new Gtk.Box (
                    Gtk.Orientation.HORIZONTAL, 8);
                row.add_css_class ("sink-row");

                string sink_icon = get_sink_icon (
                    device.icon_name);
                var row_icon = new Gtk.Image.from_icon_name (
                    sink_icon);

                string ?name = device.get_display_name ();
                if (name == null || name == "") {
                    name = device.device_description
                        ?? "Unknown";
                }
                var row_label = new Gtk.Label (name);
                row_label.set_ellipsize (
                    Pango.EllipsizeMode.END);
                row_label.set_hexpand (true);
                row_label.set_halign (Gtk.Align.START);

                row.append (row_icon);
                row.append (row_label);

                bool is_active = default_sink != null
                    && device.device_name
                        == default_sink.device_name
                    && device.port_name
                        == default_sink.port_name;
                if (is_active) {
                    var check = new Gtk.Image.from_icon_name (
                        "object-select-symbolic");
                    row.append (check);
                }

                var btn = new Gtk.Button ();
                btn.set_child (row);
                btn.add_css_class ("flat");

                btn.clicked.connect (() => {
                    client.set_default_device.begin (device);
                });

                sink_list_box.append (btn);
            }

            bool show = count > 1;
            sink_list_box.set_visible (show);
            update_reveal_visibility ();
        }
    }
}
