public struct XimperShellNotificationCenterDaemonData {
    public bool dnd;
    public bool cc_open;
    public uint count;
    public bool inhibited;
}

[DBus (name = "ru.ximperlinux.shell.NotificationCenter")]
interface CcDaemon : Object {
    public abstract bool reload_css () throws Error;

    public abstract void reload_config () throws Error;

    public abstract void hide_latest_notifications (bool close) throws DBusError, IOError;

    public abstract void hide_all_notifications () throws DBusError, IOError;

    public abstract void close_all_notifications () throws DBusError, IOError;

    public abstract uint notification_count () throws DBusError, IOError;

    public abstract bool get_dnd () throws DBusError, IOError;

    public abstract void set_dnd (bool state) throws DBusError, IOError;

    public abstract bool get_visibility () throws DBusError, IOError;

    public abstract void toggle_visibility () throws DBusError, IOError;

    public abstract bool toggle_dnd () throws DBusError, IOError;

    public abstract void set_visibility (bool value) throws DBusError, IOError;

    public abstract void latest_invoke_action (uint32 action_index) throws DBusError, IOError;

    public abstract bool set_cc_monitor (string monitor) throws DBusError, IOError;
    public abstract bool set_noti_window_monitor (string monitor) throws DBusError, IOError;

    [DBus (name = "GetSubscribeData")]
    public abstract XimperShellNotificationCenterDaemonData get_subscribe_data () throws Error;

    public signal void subscribe_v2 (uint count, bool dnd, bool cc_open, bool inhibited);

    public abstract bool add_inhibitor (string application_id) throws DBusError, IOError;
    public abstract bool remove_inhibitor (string application_id) throws DBusError, IOError;
    public abstract uint number_of_inhibitors () throws DBusError, IOError;
    public abstract bool is_inhibited () throws DBusError, IOError;
    public abstract bool clear_inhibitors () throws DBusError, IOError;
}

private CcDaemon cc_daemon = null;

private string get_user_config_path () {
    return Path.build_path (Path.DIR_SEPARATOR.to_string (),
                            Environment.get_user_config_dir (),
                            "ximper-shell", "notification-center",
                            "config.json");
}

private string get_user_style_path () {
    return Path.build_path (Path.DIR_SEPARATOR.to_string (),
                            Environment.get_user_config_dir (),
                            "ximper-shell", "notification-center",
                            "style.css");
}

private Json.Node load_json_file (string path) throws Error {
    Json.Parser parser = new Json.Parser ();
    parser.load_from_file (path);
    return parser.steal_root ();
}

private Json.Node load_config_json () throws Error {
    string user_config_path = get_user_config_path ();
    if (File.new_for_path (user_config_path).query_exists ()) {
        return load_json_file (user_config_path);
    }
    return load_json_file (Constants.CONFIG_PATH);
}

private void object_set_string_member (Json.Object object,
                                       string name,
                                       string value) {
    object.set_string_member (name, value);
}

private void object_set_boolean_member (Json.Object object,
                                        string name,
                                        bool value) {
    object.set_boolean_member (name, value);
}

private void object_set_uint_member (Json.Object object,
                                     string name,
                                     uint value) {
    object.set_int_member (name, (int64) value);
}

private bool file_exists (string path) {
    return File.new_for_path (path).query_exists ();
}

private string widget_type_from_key (string key) {
    return key.split ("#")[0];
}

private string ?widget_suffix_from_key (string key) {
    string[] parts = key.split ("#");
    if (parts.length < 2 || parts[1].length == 0) {
        return null;
    }
    return parts[1];
}

private bool metadata_array_has_type (Json.Array ?array,
                                      string type) {
    if (array == null) {
        return false;
    }

    for (uint i = 0; i < array.get_length (); i++) {
        unowned Json.Object ?object = array.get_object_element (i);
        if (object == null || !object.has_member ("type")) {
            continue;
        }
        if (object.get_string_member ("type") == type) {
            return true;
        }
    }
    return false;
}

private bool notification_daemon_enabled (Json.Object config) {
    return config.get_boolean_member_with_default (
        "notification-daemon", true);
}

private Json.Object build_style_info (string path) {
    Json.Object info = new Json.Object ();
    object_set_string_member (info, "path", path);
    object_set_boolean_member (info, "exists", file_exists (path));
    return info;
}

private void add_styles (Json.Object root) {
    Json.Object styles = new Json.Object ();
    styles.set_object_member ("default",
                              build_style_info (Constants.STYLE_PATH));
    styles.set_object_member ("user",
                              build_style_info (get_user_style_path ()));
    root.set_object_member ("styles", styles);
}

private void add_capabilities (Json.Object root) {
    Json.Object capabilities = new Json.Object ();
#if HAVE_PULSE_AUDIO
    object_set_boolean_member (capabilities, "pulse-audio", true);
#else
    object_set_boolean_member (capabilities, "pulse-audio", false);
#endif
#if HAVE_DDC
    object_set_boolean_member (capabilities, "ddc", true);
#else
    object_set_boolean_member (capabilities, "ddc", false);
#endif
    object_set_boolean_member (capabilities, "layer-shell", true);
    root.set_object_member ("capabilities", capabilities);
}

private Json.Object build_widget_entry (string key,
                                        Json.Object config,
                                        Json.Object schema) {
    string type = widget_type_from_key (key);
    Json.Object entry = new Json.Object ();
    object_set_string_member (entry, "key", key);
    object_set_string_member (entry, "type", type);
    string ?suffix = widget_suffix_from_key (key);
    if (suffix != null) {
        object_set_string_member (entry, "suffix", suffix);
    }
    object_set_boolean_member (
        entry, "known",
        metadata_array_has_type (
            schema.get_array_member ("x-ximper-widgets"), type));

    return entry;
}

private Json.Object build_tile_entry (Json.Object tile,
                                      Json.Object schema) {
    string type = tile.get_string_member_with_default ("type", "");
    Json.Object entry = new Json.Object ();
    object_set_string_member (entry, "type", type);
    object_set_boolean_member (
        entry, "known",
        metadata_array_has_type (
            schema.get_array_member (
                "x-ximper-quick-settings-tiles"), type));
    return entry;
}

private void add_preview_items (Json.Object preview,
                                Json.Object config,
                                Json.Object schema) {
    Json.Array widgets = new Json.Array ();
    Json.Array tiles = new Json.Array ();

    if (config.has_member ("widgets")) {
        unowned Json.Array configured_widgets =
            config.get_array_member ("widgets");
        for (uint i = 0; i < configured_widgets.get_length (); i++) {
            string widget = configured_widgets.get_string_element (i);
            if (widget_type_from_key (widget) == "notifications"
                    && !notification_daemon_enabled (config)) {
                continue;
            }
            widgets.add_object_element (
                build_widget_entry (
                    widget,
                    config,
                    schema));
        }
    }

    if (config.has_member ("widget-config")) {
        unowned Json.Object widget_config =
            config.get_object_member ("widget-config");
        if (widget_config != null
            && widget_config.has_member ("quick-settings")) {
            unowned Json.Object quick_settings =
                widget_config.get_object_member ("quick-settings");
            if (quick_settings != null
                && quick_settings.has_member ("tiles")) {
                unowned Json.Array configured_tiles =
                    quick_settings.get_array_member ("tiles");
                for (uint i = 0;
                     i < configured_tiles.get_length ();
                     i++) {
                    unowned Json.Object ?tile =
                        configured_tiles.get_object_element (i);
                    if (tile != null && (notification_daemon_enabled (config)
                            || tile.get_string_member_with_default ("type", "") != "dnd")) {
                        tiles.add_object_element (
                            build_tile_entry (tile, schema));
                    }
                }
            }
        }
    }

    preview.set_array_member ("widgets", widgets);
    preview.set_array_member ("quick-settings-tiles", tiles);
}

private void add_preview (Json.Object root,
                          Json.Object config,
                          Json.Object schema) {
    Json.Object preview = new Json.Object ();
    add_preview_items (preview, config, schema);
    root.set_object_member ("preview", preview);
}

private void add_runtime_status (Json.Object root) {
    Json.Object runtime = new Json.Object ();
    try {
        XimperShellNotificationCenterDaemonData data =
            cc_daemon.get_subscribe_data ();
        object_set_boolean_member (runtime, "running", true);
        object_set_boolean_member (runtime, "visible", data.cc_open);
        object_set_boolean_member (runtime, "dnd", data.dnd);
        object_set_uint_member (runtime, "count", data.count);
        object_set_boolean_member (runtime, "inhibited", data.inhibited);
    } catch (Error e) {
        object_set_boolean_member (runtime, "running", false);
        object_set_boolean_member (runtime, "visible", false);
        object_set_boolean_member (runtime, "dnd", false);
        object_set_uint_member (runtime, "count", 0);
        object_set_boolean_member (runtime, "inhibited", false);
    }
    root.set_object_member ("runtime", runtime);
}

private void add_paths (Json.Object root) {
    Json.Object paths = new Json.Object ();
    object_set_string_member (paths, "config", get_user_config_path ());
    object_set_string_member (paths, "default-config", Constants.CONFIG_PATH);
    object_set_string_member (paths, "schema", Constants.CONFIG_SCHEMA_PATH);
    root.set_object_member ("paths", paths);
}

private Json.Node ?schema_member_node (Json.Object schema, string name) {
    if (!schema.has_member (name)) {
        return null;
    }
    return schema.get_member (name).copy ();
}

private Json.Node filtered_metadata (Json.Object config, Json.Array source,
                                     string daemon_only_type) {
    Json.Array result = new Json.Array ();

    for (uint i = 0; i < source.get_length (); i++) {
        unowned Json.Object ?widget = source.get_object_element (i);
        if (widget == null) {
            continue;
        }
        if (widget.get_string_member_with_default ("type", "")
                == daemon_only_type
                && !notification_daemon_enabled (config)) {
            continue;
        }
        result.add_element (source.get_element (i).copy ());
    }

    Json.Node node = new Json.Node (Json.NodeType.ARRAY);
    node.set_array (result);
    return node;
}

private void add_schema_metadata (Json.Object root,
                                  Json.Object config,
                                  Json.Object schema) {
    Json.Object metadata = new Json.Object ();

    metadata.set_member ("widgets",
                         filtered_metadata (config, schema.get_array_member ("x-ximper-widgets"),
                                            "notifications"));

    if (schema.has_member ("x-ximper-quick-settings-tiles")) {
        metadata.set_member ("quick-settings-tiles",
                             filtered_metadata (config, schema.get_array_member ("x-ximper-quick-settings-tiles"),
                                                "dnd"));
    }

    Json.Node ?node = schema_member_node (schema, "properties");
    if (node != null) {
        metadata.set_member ("properties", node);
    }

    root.set_object_member ("metadata", metadata);
}

private void print_describe () throws Error {
    Json.Object root = new Json.Object ();
    Json.Node config = load_config_json ();
    Json.Node schema = load_json_file (Constants.CONFIG_SCHEMA_PATH);

    root.set_member ("config", config);
    add_runtime_status (root);
    add_paths (root);
    add_styles (root);
    add_capabilities (root);
    add_schema_metadata (root, config.get_object (), schema.get_object ());
    add_preview (
        root, config.get_object (), schema.get_object ());

    Json.Node root_node = new Json.Node (Json.NodeType.OBJECT);
    root_node.set_object (root);
    Json.Generator generator = new Json.Generator ();
    generator.set_pretty (true);
    generator.set_root (root_node);
    print (generator.to_data (null));
    print ("\n");
}

private void print_help (string[] args) {
    print ("Usage:\n");
    print ("  %s <OPTION>\n".printf (args[0]));
    print ("Help:\n");
    print ("  -h, \t --help \t\t\t Show help options\n");
    print ("  -v, \t --version \t\t\t Prints version\n");
    print ("Options:\n");
    print ("      \t --describe \t\t\t Print config, runtime state, and schema metadata as JSON\n");
    print ("  -R, \t --reload-config \t\t Reload the config file\n");
    print ("  -rs, \t --reload-css \t\t\t Reload the css file. Location change requires restart\n");
    print ("  -t, \t --toggle-panel \t\t Toggle the notification panel\n");
    print ("  -op, \t --open-panel \t\t\t Opens the notification panel\n");
    print ("  -cp, \t --close-panel \t\t\t Closes the notification panel\n");
    print ("  -d, \t --toggle-dnd \t\t\t Toggle and print the current dnd state\n");
    print ("  -D, \t --get-dnd \t\t\t Print the current dnd state\n");
    print ("  -dn, \t --dnd-on \t\t\t Turn dnd on and print the new dnd state\n");
    print ("  -df, \t --dnd-off \t\t\t Turn dnd off and print the new dnd state\n");
    print ("  -I, \t --get-inhibited \t\t Print if currently inhibited or not\n");
    print ("  -In, \t --get-num-inhibitors \t\t Print number of inhibitors\n");
    print ("  -Ia, \t --inhibitor-add [APP_ID] \t Add an inhibitor\n");
    print ("  -Ir, \t --inhibitor-remove [APP_ID] \t Remove an inhibitor\n");
    print ("  -Ic, \t --inhibitors-clear \t\t Clears all inhibitors\n");
    print ("  -c, \t --count \t\t\t Print the current notification count\n");
    print (
        "      \t --hide-latest \t\t\t Hides latest notification. Still shown in Control Center\n");
    print ("      \t --hide-all \t\t\t Hides all notifications. Still shown in Control Center\n");
    print ("      \t --close-latest \t\t Closes latest notification\n");
    print ("  -C, \t --close-all \t\t\t Closes all notifications\n");
    print ("  -a, \t --action [ACTION_INDEX]\t " +
           "Invokes the action [ACTION_INDEX] of the latest notification\n");
    print ("  -sw, \t --skip-wait \t\t\t Doesn't wait when ximper-shell-notification-center hasn't been started\n");
    print ("  -s, \t --subscribe \t\t\t Subscribe to notification add and close events\n");
    print ("  -swb,  --subscribe-waybar \t\t Subscribe to notification add and close events "
           + "with waybar support. Read README for example\n");
    print ("      \t --change-cc-monitor \t\t Changes the preferred control center monitor"
           + " (resets on config reload)\n");
    print ("      \t --change-noti-monitor \t\t Changes the preferred notification monitor"
           + " (resets on config reload)\n");
}

private void on_subscribe (uint count, bool dnd, bool cc_open, bool inhibited) {
    stdout.printf (
        "{ \"count\": %u, \"dnd\": %s, \"visible\": %s, \"inhibited\": %s }\n",
        count, dnd.to_string (), cc_open.to_string (), inhibited.to_string ());
    stdout.flush ();
}

private void print_subscribe () {
    try {
        XimperShellNotificationCenterDaemonData data = cc_daemon.get_subscribe_data ();
        on_subscribe (data.count, data.dnd, data.cc_open, data.inhibited);
    } catch (Error e) {
        on_subscribe (0, false, false, false);
    }
}

private void on_subscribe_waybar (uint count, bool dnd, bool cc_open, bool inhibited) {
    string state = (dnd ? "dnd-" : "")
        + (inhibited ? "inhibited-" : "")
        + (count > 0 ? "notification" : "none");

    string tooltip = "";
    if (count > 0) {
        tooltip = "%u Notification%s".printf (count, count > 1 ? "s" : "");
    }

    string _class = "\"%s\"".printf (state);
    if (cc_open) {
        _class = "[%s, \"cc-open\"]".printf (_class);
    }

    print (
        "{\"text\": \"%u\", \"alt\": \"%s\", \"tooltip\": \"%s\", \"class\": %s}\n",
        count, state, tooltip, _class);
}

private void print_subscribe_waybar () {
    try {
        XimperShellNotificationCenterDaemonData data = cc_daemon.get_subscribe_data ();
        on_subscribe_waybar (data.count, data.dnd, data.cc_open, data.inhibited);
    } catch (Error e) {
        on_subscribe_waybar (0, false, false, false);
    }
}

public int command_line (ref string[] args, bool skip_wait) {
    // Used to know how many args the current command consumed
    int used_args = 1;
    try {
        if (args.length < 1) {
            print_help (args);
            Process.exit (1);
        }
        switch (args[0]) {
            case "--help":
            case "-h":
                print_help (args);
                break;
            case "--version":
            case "-v":
                stdout.printf ("%s\n", Constants.VERSION);
                break;
            case "--describe":
                print_describe ();
                break;
            case "--reload-config":
            case "-R":
                cc_daemon.reload_config ();
                break;
            case "--reload-css":
            case "-rs":
                stdout.printf ("CSS reload success: %s\n",
                               cc_daemon.reload_css ().to_string ());
                break;
            case "--count":
            case "-c":
                print (cc_daemon.notification_count ().to_string ());
                break;
            case "--close-latest":
                cc_daemon.hide_latest_notifications (true);
                break;
            case "--hide-latest":
                cc_daemon.hide_latest_notifications (false);
                break;
            case "--hide-all":
                cc_daemon.hide_all_notifications ();
                break;
            case "--close-all":
            case "-C":
                cc_daemon.close_all_notifications ();
                break;
            case "--toggle-panel":
            case "-t":
                cc_daemon.toggle_visibility ();
                break;
            case "--open-panel":
            case "-op":
                cc_daemon.set_visibility (true);
                break;
            case "--close-panel":
            case "-cp":
                cc_daemon.set_visibility (false);
                break;
            case "--toggle-dnd":
            case "-d":
                print (cc_daemon.toggle_dnd ().to_string ());
                break;
            case "--get-dnd":
            case "-D":
                print (cc_daemon.get_dnd ().to_string ());
                break;
            case "--dnd-on":
            case "-dn":
                cc_daemon.set_dnd (true);
                print (cc_daemon.get_dnd ().to_string ());
                break;
            case "--dnd-off":
            case "-df":
                cc_daemon.set_dnd (false);
                print (cc_daemon.get_dnd ().to_string ());
                break;
            case "--action":
            case "-a":
                int action_index = 0;
                if (args.length >= 2) {
                    used_args++;
                    action_index = int.parse (args[1]);
                }
                cc_daemon.latest_invoke_action ((uint32) action_index);
                break;
            case "--get-inhibited":
            case "-I":
                print (cc_daemon.is_inhibited ().to_string ());
                break;
            case "--get-num-inhibitors":
            case "-In":
                print (cc_daemon.number_of_inhibitors ().to_string ());
                break;
            case "--inhibitor-add":
            case "-Ia":
                if (args.length < 2) {
                    stderr.printf ("Application ID needed!");
                    Process.exit (1);
                }
                used_args++;
                if (cc_daemon.add_inhibitor (args[1])) {
                    print ("Added inhibitor: \"%s\"", args[1]);
                    break;
                }
                stderr.printf ("Inhibitor: \"%s\" already added!…", args[1]);
                break;
            case "--inhibitor-remove":
            case "-Ir":
                if (args.length < 2) {
                    stderr.printf ("Application ID needed!");
                    Process.exit (1);
                }
                used_args++;
                if (cc_daemon.remove_inhibitor (args[1])) {
                    print ("Removed inhibitor: \"%s\"", args[1]);
                    break;
                }
                stderr.printf ("Inhibitor: \"%s\" does not exist!…", args[1]);
                break;
            case "inhibitors-clear":
            case "--inhibitors-clear":
            case "-Ic":
                if (cc_daemon.clear_inhibitors ()) {
                    print ("Cleared all inhibitors");
                    break;
                }
                print ("No inhibitors to clear…");
                break;
            case "--subscribe":
            case "-s":
                cc_daemon.subscribe_v2.connect (on_subscribe);
                var data = cc_daemon.get_subscribe_data ();
                on_subscribe (data.count,
                              data.dnd,
                              data.cc_open,
                              data.inhibited);
                var loop = new MainLoop ();
                Bus.watch_name (
                    BusType.SESSION,
                    "ru.ximperlinux.shell.NotificationCenter",
                    BusNameWatcherFlags.NONE,
                    print_subscribe,
                    print_subscribe);
                loop.run ();
                break;
            case "--subscribe-waybar":
            case "-swb":
                cc_daemon.subscribe_v2.connect (on_subscribe_waybar);
                var loop = new MainLoop ();
                Bus.watch_name (
                    BusType.SESSION,
                    "ru.ximperlinux.shell.NotificationCenter",
                    BusNameWatcherFlags.NONE,
                    print_subscribe_waybar,
                    print_subscribe_waybar);
                loop.run ();
                break;
            case "--change-cc-monitor":
                if (args.length < 2) {
                    stderr.printf ("Monitor connector name needed!");
                    Process.exit (1);
                }
                used_args++;
                if (cc_daemon.set_cc_monitor (args[1])) {
                    print ("Changed monitor to: \"%s\"", args[1]);
                    break;
                }
                stderr.printf ("Could not find monitor: \"%s\"!", args[1]);
                break;
            case "--change-noti-monitor":
                if (args.length < 2) {
                    stderr.printf ("Monitor connector name needed!");
                    Process.exit (1);
                }
                used_args++;
                if (cc_daemon.set_noti_window_monitor (args[1])) {
                    print ("Changed monitor to: \"%s\"", args[1]);
                    break;
                }
                stderr.printf ("Could not find monitor: \"%s\"!", args[1]);
                break;
            default:
                printerr ("Unknown command: \"%s\"\n", args[0]);
                print_help (args);
                break;
        }
    } catch (Error e) {
        stderr.printf (e.message + "\n");
        if (skip_wait) {
            Process.exit (1);
        }
        return 1;
    }

    args = args[used_args:];
    return 0;
}

void print_connection_error () {
    stderr.printf (
        "Could not connect to CC service. Will wait for connection…\n");
}

int try_connect (owned string[] args) {
    try {
        cc_daemon = Bus.get_proxy_sync (
            BusType.SESSION,
            "ru.ximperlinux.shell.NotificationCenter",
            "/ru/ximperlinux/shell/NotificationCenter");

        bool skip_wait = "--skip-wait" in args || "-sw" in args;
        bool one_arg = true;
        while (args.length > 0) {
            if (args[0] == "--skip-wait" || args[0] == "-sw") {
                args = args[1 :];
                continue;
            }
            if (!one_arg) {
                // Separate each command output
                print ("\n");
            }
            if (command_line (ref args, skip_wait) == 1) {
                print_connection_error ();
                return 1;
            }
            one_arg = false;
        }
        // Should only be reached if the args only contains --skip-wait or -sw
        if (one_arg) {
            stderr.printf ("Skipping wait, but with no action.");
        }
        return 0;
    } catch (Error e) {
        if ("--skip-wait" in args || "-sw" in args) {
            printerr ("%s\n", e.message);
            return 1;
        }
        print_connection_error ();
        return 1;
    }
}

public int main (string[] args) {
    if (try_connect (args[1 :]) == 1) {
        if ("--skip-wait" in args || "-sw" in args) {
            return 1;
        }
        MainLoop loop = new MainLoop ();
        Bus.watch_name (
            BusType.SESSION,
            "ru.ximperlinux.shell.NotificationCenter",
            BusNameWatcherFlags.NONE,
            (conn, name, name_owner) => {
            if (try_connect (args[1 :]) == 0) {
                loop.quit ();
            }
        },
            null);
        loop.run ();
    }
    return 0;
}
