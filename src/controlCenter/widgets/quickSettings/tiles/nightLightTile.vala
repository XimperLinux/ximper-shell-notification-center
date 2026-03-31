namespace XimperShellNotificationCenter.Widgets {
    public class NightLightTile : QuickSettingsTile {
        private const int NEUTRAL_TEMP = 6000;
        private int temperature = 4500;
        private bool _is_available = false;

        public NightLightTile (Json.Object ?cfg) {
            base ("night-light-disabled-symbolic",
                  _("Night Light"));

            if (cfg != null) {
                int temp = (int) cfg.get_int_member_with_default (
                    "temperature", 0);
                if (temp > 0) {
                    temperature = temp;
                }
            }
        }

        public override bool is_available () {
            return _is_available;
        }

        public override void on_cc_visibility_change (
                bool visible) {
            if (visible) {
                check_and_sync.begin ();
            }
        }

        private async void check_and_sync () {
            string msg;
            bool ok = yield Functions.execute_command (
                "pgrep -x hyprsunset", {}, out msg);
            bool was_available = _is_available;
            _is_available = ok
                && msg.strip ().length > 0;

            if (_is_available) {
                yield sync_state ();
            }

            if (was_available != _is_available) {
                // Trigger grid rebuild
                set_visible (_is_available);
            }
        }

        private async void sync_state () {
            string msg;
            yield Functions.execute_command (
                "hyprctl hyprsunset temperature",
                {}, out msg);
            int current = int.parse (msg.strip ());
            active = (current < NEUTRAL_TEMP);
            update_icon ();
        }

        public override void on_toggle () {
            active = !active;
            update_icon ();
            if (active) {
                run_hyprctl.begin (
                    "hyprctl hyprsunset temperature %d"
                        .printf (temperature));
            } else {
                run_hyprctl.begin (
                    "hyprctl hyprsunset identity");
            }
        }

        private void update_icon () {
            icon.set_from_icon_name (active
                ? "night-light-symbolic"
                : "night-light-disabled-symbolic");
        }

        private async void run_hyprctl (string cmd) {
            string msg;
            yield Functions.execute_command (cmd, {}, out msg);
        }
    }
}
