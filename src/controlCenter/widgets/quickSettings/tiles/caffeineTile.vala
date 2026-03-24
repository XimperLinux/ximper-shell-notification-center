namespace XimperShellNotificationCenter.Widgets {
    [DBus (name = "org.freedesktop.login1.Manager")]
    interface Login1Manager : Object {
        public abstract UnixInputStream inhibit (
            string what, string who, string why, string mode)
            throws GLib.Error;
    }

    public class CaffeineTile : QuickSettingsTile {
        private Login1Manager ?login1 = null;
        private int inhibit_fd = -1;

        public CaffeineTile (Json.Object ?cfg) {
            base ("display-brightness-symbolic",
                  _("Caffeine"));
            update_icon ();

            try {
                login1 = Bus.get_proxy_sync (BusType.SYSTEM,
                    "org.freedesktop.login1",
                    "/org/freedesktop/login1");
            } catch (Error e) {
                warning ("logind not available: %s", e.message);
                set_visible (false);
            }
        }

        private void update_icon () {
            icon.set_from_icon_name (active
                ? "caffeine-on-symbolic"
                : "caffeine-off-symbolic");
        }

        public override void on_toggle () {
            if (login1 == null) return;

            if (active) {
                release_inhibitor ();
            } else {
                acquire_inhibitor ();
            }
        }

        private void acquire_inhibitor () {
            try {
                var stream = login1.inhibit (
                    "idle",
                    "ximper-shell-notification-center",
                    _("Caffeine mode"),
                    "block");
                inhibit_fd = stream.fd;
                // Prevent stream from closing fd on dispose
                stream.set_close_fd (false);
                active = true;
                update_icon ();
            } catch (Error e) {
                warning ("Failed to inhibit idle: %s",
                         e.message);
            }
        }

        private void release_inhibitor () {
            if (inhibit_fd >= 0) {
                Posix.close (inhibit_fd);
                inhibit_fd = -1;
            }
            active = false;
            update_icon ();
        }

        public override void on_cc_visibility_change (bool visible) {
        }
    }
}
