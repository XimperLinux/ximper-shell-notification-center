namespace XimperShellNotificationCenter.Widgets {
    public class DndTile : QuickSettingsTile {
        public DndTile (Json.Object ?cfg) {
            base ("notifications-disabled-symbolic",
                  _("Do Not Disturb"));
            active = noti_daemon.dnd;
            update_icon ();

            noti_daemon.on_dnd_toggle.connect ((dnd) => {
                active = dnd;
                update_icon ();
            });
        }

        public override bool is_available () {
            return notifications_widget != null;
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
