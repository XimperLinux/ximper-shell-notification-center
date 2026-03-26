namespace XimperShellNotificationCenter.Widgets {
    [GtkTemplate (ui = "/ru/ximperlinux/shell/NotificationCenter/ui/widgets/label.ui")]
    public class Label : BaseWidget {
        public override string widget_name {
            get {
                return "label";
            }
        }

        [GtkChild]
        unowned Gtk.Label label_widget;

        // Default config values
        string text = "Label Text";
        int max_lines = 5;

        public Label (string suffix) {
            base (suffix);

            Json.Object ?config = get_config (this);
            if (config != null) {
                // Get text
                string ?text = get_prop<string> (config, "text");
                if (text != null) {
                    this.text = text;
                }
                // Get max lines
                int ?max_lines = get_prop<int> (config, "max-lines");
                if (max_lines != null) {
                    this.max_lines = max_lines;
                }
            }

            label_widget.set_text (text);
            label_widget.set_lines (max_lines);
        }
    }
}
