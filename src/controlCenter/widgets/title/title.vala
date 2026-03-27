namespace XimperShellNotificationCenter.Widgets {
    [GtkTemplate (ui = "/ru/ximperlinux/shell/NotificationCenter/ui/widgets/title.ui")]
    public class Title : BaseWidget {
        public override string widget_name {
            get {
                return "title";
            }
        }

        [GtkChild]
        unowned Gtk.Label title_widget;
        [GtkChild]
        unowned Gtk.Button clear_all_button;

        // Default config values
        string title;
        bool has_clear_all_button = true;

        public Title (string suffix) {
            base (suffix);
            title = _("Notifications");

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

            clear_all_button.set_visible (
                has_clear_all_button
                && notifications_widget != null);

            if (notifications_widget != null) {
                clear_all_button.set_sensitive (
                    !notifications_widget.is_empty ());
                ximper_shell_notification_center_daemon
                    .subscribe_v2.connect ((count) => {
                    clear_all_button.set_sensitive (count > 0);
                });
            }
        }

        [GtkCallback]
        private void on_clear_all_clicked () {
            noti_daemon.request_dismiss_all_notifications (ClosedReasons.DISMISSED);
        }
    }
}
