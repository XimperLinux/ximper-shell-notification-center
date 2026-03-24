namespace XimperShellNotificationCenter.Widgets {
    public class NightLightTile : QuickSettingsTile {
        private const int NEUTRAL_TEMP = 6000;
        private int temperature = 4500;

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
            try {
                string output;
                Process.spawn_command_line_sync (
                    "pgrep -x hyprsunset",
                    out output, null, null);
                return output.strip ().length > 0;
            } catch (SpawnError e) {
                return false;
            }
        }

        public override void on_cc_visibility_change (
                bool visible) {
            if (visible && is_available ()) {
                sync_state ();
            }
        }

        private void sync_state () {
            try {
                string output;
                Process.spawn_command_line_sync (
                    "hyprctl hyprsunset temperature",
                    out output, null, null);
                int current = int.parse (output.strip ());
                active = (current < NEUTRAL_TEMP);
                update_icon ();
            } catch (SpawnError e) {
                debug ("Failed to get temperature: %s",
                       e.message);
            }
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
