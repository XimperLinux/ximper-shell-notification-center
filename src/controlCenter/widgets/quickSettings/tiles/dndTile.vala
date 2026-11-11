namespace XimperShellNotificationCenter.Widgets {
    public class DndTile : QuickSettingsTile {
        public DndTile (Json.Object ?cfg) {
            base ("notifications-disabled-symbolic",
                  _("Do Not Disturb"));
            active = noti_daemon.dnd;
            update_icon ();
            app.notify["notification-service-active"].connect (on_service_changed);

            noti_daemon.on_dnd_toggle.connect ((dnd) => {
                active = dnd;
                update_icon ();
            });
        }

        public override bool is_available () {
            return app.notification_service_active;
        }

        private void on_service_changed () {
            availability_changed ();
        }

        private void update_icon () {
            icon.set_from_icon_name (active
                ? "notifications-disabled-symbolic"
                : "preferences-system-notifications-symbolic");
        }

        public override void on_toggle () {
            noti_daemon.dnd = !noti_daemon.dnd;
        }
    }
}
