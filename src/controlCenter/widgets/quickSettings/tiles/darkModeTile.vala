namespace XimperShellNotificationCenter.Widgets {
    public class DarkModeTile : QuickSettingsTile {
        private Settings interface_settings;

        public DarkModeTile (Json.Object ?cfg) {
            base ("dark-mode-symbolic",
                  _("Dark Style"));

            interface_settings = new Settings (
                "org.gnome.desktop.interface");
            sync_state ();

            interface_settings.changed["color-scheme"].connect (
                () => {
                sync_state ();
            });
        }

        private void sync_state () {
            string scheme = interface_settings.get_string (
                "color-scheme");
            active = (scheme == "prefer-dark");
        }

        public override void on_toggle () {
            string new_scheme = active
                ? "default" : "prefer-dark";
            interface_settings.set_string (
                "color-scheme", new_scheme);
        }
    }
}
