namespace XimperShellNotificationCenter.Widgets {
    public class CommandTile : QuickSettingsTile {
        private string command = "";
        private string update_command = "";

        public CommandTile (Json.Object ?cfg) {
            string icon_name = "application-x-executable-symbolic";
            string label = "";
            string cmd = "";
            string ucmd = "";
            bool initial_active = false;

            if (cfg != null) {
                if (cfg.has_member ("icon")) {
                    icon_name = cfg.get_string_member ("icon");
                }
                if (cfg.has_member ("label")) {
                    label = cfg.get_string_member ("label");
                } else {
                    warning ("Command tile missing 'label'");
                }
                cmd = cfg.get_string_member_with_default (
                    "command", "");
                ucmd = cfg.get_string_member_with_default (
                    "update-command", "");
                initial_active = cfg.get_boolean_member_with_default (
                    "active", false);
            }

            base (icon_name, label);
            command = cmd;
            update_command = ucmd;
            active = initial_active;
        }

        public override void on_toggle () {
            active = !active;
            string[] env = {
                "XSNC_TOGGLE_STATE=" + active.to_string ()
            };
            run_command.begin (command, env);
        }

        private async void run_command (string cmd, string[] env) {
            string msg;
            yield Functions.execute_command (cmd, env, out msg);
        }

        public override void on_cc_visibility_change (bool visible) {
            if (!visible || update_command == "") {
                return;
            }
            run_update.begin ();
        }

        private async void run_update () {
            string[] env = {
                "XSNC_TOGGLE_STATE=" + active.to_string ()
            };
            string msg;
            yield Functions.execute_command (
                update_command, env, out msg);
            active = (msg.strip ().up () == "TRUE");
        }
    }
}
