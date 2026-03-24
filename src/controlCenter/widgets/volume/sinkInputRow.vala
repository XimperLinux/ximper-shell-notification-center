namespace XimperShellNotificationCenter.Widgets {
    public class SinkInputRow : Gtk.ListBoxRow {
        Gtk.Box container;
        Gtk.Image icon = new Gtk.Image ();
        Gtk.Scale scale = new Gtk.Scale.with_range (
            Gtk.Orientation.HORIZONTAL, 0, 100, 1);

        public unowned PulseSinkInput sink_input;

        private unowned PulseDaemon client;

        public SinkInputRow (PulseSinkInput sink_input,
                             PulseDaemon client) {
            this.client = client;

            set_activatable (false);

            update (sink_input);

            scale.draw_value = false;
            scale.set_hexpand (true);

            container = new Gtk.Box (
                Gtk.Orientation.HORIZONTAL, 0);
            container.append (icon);
            container.append (scale);

            set_child (container);

            scale.value_changed.connect (() => {
                client.set_sink_input_volume (
                    sink_input, (float) scale.get_value ());
                scale.tooltip_text =
                    ((int) scale.get_value ()).to_string ();
            });
        }

        public void update (PulseSinkInput sink_input) {
            this.sink_input = sink_input;

            string icon_name = "application-x-executable";
            if (sink_input.application_icon_name != null) {
                icon_name = sink_input.application_icon_name;
            } else if (sink_input.application_binary != null) {
                var theme = Gtk.IconTheme.get_for_display (
                    Gdk.Display.get_default ());
                if (theme.has_icon (
                        sink_input.application_binary)) {
                    icon_name = sink_input.application_binary;
                }
            }
            icon.set_from_icon_name (icon_name);
            icon.set_tooltip_text (sink_input.name);

            scale.set_value (sink_input.volume);
            scale.tooltip_text =
                ((int) scale.get_value ()).to_string ();
        }
    }
}
