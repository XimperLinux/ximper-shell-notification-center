namespace XimperShellNotificationCenter.Widgets {
    [GtkTemplate (ui = "/ru/ximperlinux/shell/NotificationCenter/ui/widgets/inhibitors.ui")]
    public class Inhibitors : BaseWidget {
        public override string widget_name {
            get {
                return "inhibitors";
            }
        }

        [GtkChild]
        unowned Gtk.Label title_widget;
        [GtkChild]
        unowned Gtk.Button clear_all_button;

        // Default config values
        string title;
        bool has_clear_all_button = true;

        public Inhibitors (string suffix) {
            base (suffix);

            ximper_shell_notification_center_daemon.inhibited_changed.connect ((length) => {
                if (!ximper_shell_notification_center_daemon.inhibited) {
                    hide ();
                    return;
                }
                show ();
                title_widget.set_text ("%s %u".printf (title, length));
            });

            reload_config ();

            hide ();
        }

        public override void reload_config () {
            title = _("Inhibitors");
            has_clear_all_button = true;

            Json.Object ?config = get_config (this);
            if (config != null) {
                // Get title
                string ?title = get_prop<string> (config, "text");
                if (title != null) {
                    this.title = title;
                }
                // Get has clear-all-button
                bool found_clear_all;
                bool ?has_clear_all_button = get_prop<bool> (
                    config, "clear-all-button", out found_clear_all);
                if (found_clear_all) {
                    this.has_clear_all_button = has_clear_all_button;
                }
            }

            title_widget.set_text (title);
            clear_all_button.set_visible (has_clear_all_button);
        }

        [GtkCallback]
        private void on_clear_inhibitors_clicked () {
            try {
                ximper_shell_notification_center_daemon.clear_inhibitors ();
            } catch (Error e) {
                critical ("Error: %s\n", e.message);
            }
        }
    }
}
