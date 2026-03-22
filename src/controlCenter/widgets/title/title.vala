namespace XimperShellNotificationCenter.Widgets {
    public class Title : BaseWidget {
        public override string widget_name {
            get {
                return "title";
            }
        }

        Gtk.Label title_widget;
        Gtk.Button clear_all_button;

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

            title_widget = new Gtk.Label (title);
            title_widget.set_hexpand (true);
            title_widget.set_halign (Gtk.Align.START);
            append (title_widget);

            if (has_clear_all_button) {
                clear_all_button = new Gtk.Button ();
                var btn_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
                btn_box.append (new Gtk.Image.from_icon_name (
                    "edit-clear-all-symbolic"));
                btn_box.append (new Gtk.Label (_("Clear All")));
                clear_all_button.set_child (btn_box);
                clear_all_button.clicked.connect (() => {
                    noti_daemon.request_dismiss_all_notifications (ClosedReasons.DISMISSED);
                });
                clear_all_button.set_sensitive (!notifications_widget.is_empty ());

                ximper_shell_notification_center_daemon.subscribe_v2.connect ((count) => {
                    clear_all_button.set_sensitive (count > 0);
                });
                clear_all_button.set_can_focus (false);
                clear_all_button.valign = Gtk.Align.CENTER;
                // Backwards compatible towards older CSS stylesheets
                clear_all_button.add_css_class ("control-center-clear-all");
                append (clear_all_button);
            }
        }
    }
}
