namespace XimperShellNotificationCenter.Widgets {
    public class CommandTile : QuickSettingsTile {
        private string command = "";
        private string update_command = "";

        public CommandTile (Json.Object ?cfg) {
            string icon_name = "application-x-executable-symbolic";
            string label = "";

            if (cfg != null) {
                string ?i = cfg.get_string_member_with_default (
                    "icon", null);
                if (i != null) icon_name = i;
                string ?l = cfg.get_string_member_with_default (
                    "label", null);
                if (l != null) {
                    label = l;
                } else {
                    warning ("Command tile missing 'label'");
                }
                command = cfg.get_string_member_with_default (
                    "command", "");
                update_command = cfg.get_string_member_with_default (
                    "update-command", "");
                active = cfg.get_boolean_member_with_default (
                    "active", false);
            }

            base (icon_name, label);
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
