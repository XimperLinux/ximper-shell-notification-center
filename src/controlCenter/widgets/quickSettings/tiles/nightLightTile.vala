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

            _is_available =
                Environment.find_program_in_path (
                    "hyprsunset") != null;
        }

        public override bool is_available () {
            return _is_available;
        }

        public override void on_cc_visibility_change (
                bool visible) {
            if (visible && _is_available) {
                sync_state.begin ();
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
