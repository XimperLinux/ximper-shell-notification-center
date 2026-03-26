namespace XimperShellNotificationCenter {
    [GtkTemplate (ui = "/ru/ximperlinux/shell/NotificationCenter/ui/notification_close_button.ui")]
    public class NotificationCloseButton : Adw.Bin {
        [GtkChild]
        unowned Gtk.Revealer revealer;
        public signal void clicked ();

        [GtkCallback]
        private void on_child_revealed () {
            set_visible (revealer.reveal_child);
        }

        [GtkCallback]
        private void on_clicked () {
            clicked ();
        }

        public void set_reveal (bool state) {
            if (state == revealer.reveal_child) {
                set_visible (state);
                return;
            }

            if (state) {
                set_visible (true);
            }
            revealer.set_reveal_child (state);
        }

        public void set_transition_duration (uint duration) {
            revealer.set_transition_duration (duration);
        }
    }
}
