namespace XimperShellNotificationCenter {
    static NotiDaemon noti_daemon;
    static XimperShellNotificationCenterDaemon ximper_shell_notification_center_daemon;
    static Widgets.Notifications notifications_widget;
    static ControlCenter control_center;
    static NotificationWindow floating_notifications;

    static unowned ListModel ?monitors = null;
    static NotificationCenter app;
    static Settings self_settings;

    static HashTable<string, unowned Gdk.PixbufFormat> pixbuf_mime_types;

    // Args
    static string ?style_path;
    static string ?config_path;
    // Dev args
    static bool skip_packaged_css = false;
    static string ?custom_packaged_css;

    private struct EnvironmentVariable {
        string name;

        public EnvironmentVariable (string name) {
            this.name = name;
        }

        public string to_string (string[] envp) {
            return "%s=%s".printf (name, Environ.get_variable (envp, name) ?? "");
        }
    }

    public class NotificationCenter : Gtk.Application {
        private bool activated = false;
        private Array<BlankWindow> blank_windows = new Array<BlankWindow> ();
        private DBusConnection session_bus;
        private uint notification_name_id = 0;
        private uint notification_object_id = 0;

        // Only set on start due to some limitations of GtkLayerShell
        public bool use_layer_shell = true;
        public bool has_layer_on_demand = true;

        public XdgActivationHelper xdg_activation;

        public signal void config_reload (ConfigModel ?old_config, ConfigModel new_config);

        private BusNameOwnerFlags bus_name_flags = BusNameOwnerFlags.NONE;

        public NotificationCenter (bool replace) {
            Object (
                application_id : "ru.ximperlinux.shell.NotificationCenter",
                flags: ApplicationFlags.DEFAULT_FLAGS
                | ApplicationFlags.ALLOW_REPLACEMENT
                | (replace ? ApplicationFlags.REPLACE : 0)
            );

            if (replace) {
                bus_name_flags = BusNameOwnerFlags.REPLACE;
            }

            try {
                register ();
                if (get_is_remote ()) {
                    printerr ("An instance of Ximper Shell Notification Center is already running!\n");
                    Process.exit (1);
                }
            } catch (Error e) {
                error (e.message);
            }
        }

        public override void activate () {
            if (activated) {
                return;
            }
            activated = true;
            init.begin ();
        }

        private async void init () {
            Functions.load_css (style_path);

            pixbuf_mime_types =
                new HashTable<string, unowned Gdk.PixbufFormat> (str_hash, str_equal);
            SList<weak Gdk.PixbufFormat> formats = Gdk.Pixbuf.get_formats ();
            foreach (weak Gdk.PixbufFormat format in formats) {
                foreach (string mime_type in format.get_mime_types ()) {
                    pixbuf_mime_types.set (mime_type, format);
                }
            }

            hold ();

            unowned Gdk.Display ?display = Gdk.Display.get_default ();
            if (display == null) {
                error ("Could not get Display!");
            }
            monitors = display.get_monitors ();
            assert_nonnull (monitors);
            print_monitors ();

            use_layer_shell = ConfigModel.instance.layer_shell;
            has_layer_on_demand = use_layer_shell &&
                GtkLayerShell.get_protocol_version () >= 4;

            try {
                session_bus = Bus.get_sync (GLib.BusType.SESSION, null);
            } catch (Error e) {
                error ("Could not connect to DBus!... (%s)\n", e.message);
            }

            noti_daemon = new NotiDaemon ();
            ximper_shell_notification_center_daemon = new XimperShellNotificationCenterDaemon ();

            // Ximper Shell Notification Center Daemon
            // Name is already owned by GApplication via register()
            try {
                session_bus.register_object (
                    "/ru/ximperlinux/shell/NotificationCenter",
                    ximper_shell_notification_center_daemon);
            } catch (Error e) {
                error ("Could not register CC service: \"%s\"", e.message);
            }

            xdg_activation = new XdgActivationHelper ();

            sync_notification_daemon ();

            config_reload.connect ((old, config) => {
                sync_notification_daemon ();
            });
            control_center = new ControlCenter ();
            noti_daemon.on_dnd_toggle.connect (on_dnd_toggle);
            // Update on start
            ximper_shell_notification_center_daemon.emit_subscribe ();

            config_reload.connect ((old, config) => {
                reload_blank_windows ();
            });

            if (use_layer_shell) {
                monitors.items_changed.connect (monitors_changed);
                monitors_changed (0, 0, monitors.get_n_items ());
            }
        }

        private void ensure_notification_ui () {
            if (notifications_widget == null) {
                notifications_widget = new Widgets.Notifications ();
            }
            if (floating_notifications == null) {
                floating_notifications = new NotificationWindow ();
                add_window (floating_notifications);
            }
        }

        private void on_dnd_toggle (bool dnd) {
            if (dnd && floating_notifications != null && floating_notifications.visible) {
                noti_daemon.remove_all_floating_notifications (true, (noti) => {
                    return !noti.param.bypasses_dnd ();
                });
            }
            ximper_shell_notification_center_daemon.emit_subscribe ();
        }

        private void enable_notification_daemon () {
            ensure_notification_ui ();

            if (notification_name_id != 0) {
                return;
            }

            notification_name_id = Bus.own_name_on_connection (
                session_bus,
                "org.freedesktop.Notifications",
                bus_name_flags,
                () => {
                if (!ConfigModel.instance.notification_daemon) {
                    return;
                }
                try {
                    if (notification_object_id == 0) {
                        notification_object_id = session_bus.register_object (
                            "/org/freedesktop/Notifications",
                            noti_daemon);
                    }
                } catch (Error e) {
                    error ("Could not register notification service: \"%s\"", e.message);
                }
            },
                () => {
                stderr.printf (
                    "Could not acquire notification name. " +
                    "Please close any other notification daemon " +
                    "like mako or dunst\n");
                notification_name_id = 0;
            });
        }

        private void disable_notification_daemon () {
            if (notification_object_id != 0) {
                session_bus.unregister_object (notification_object_id);
                notification_object_id = 0;
            }
            if (notification_name_id != 0) {
                Bus.unown_name (notification_name_id);
                notification_name_id = 0;
            }
            if (floating_notifications != null) {
                floating_notifications.remove_all_notifications (false, null);
                remove_window (floating_notifications);
                floating_notifications.close ();
                floating_notifications = null;
            }
            if (notifications_widget != null) {
                notifications_widget.remove_all_notifications (false);
                notifications_widget.on_removed ();
                notifications_widget = null;
            }
        }

        private void sync_notification_daemon () {
            if (ConfigModel.instance.notification_daemon) {
                enable_notification_daemon ();
            } else {
                disable_notification_daemon ();
            }
        }

        private void monitors_changed (uint position, uint removed, uint added) {
            info ("Monitors Changed:");
            print_monitors ();

            bool visible = control_center.get_visibility ();

            for (uint i = 0; i < removed; i++) {
                unowned BlankWindow win = blank_windows.index (position);
                win.close ();
                blank_windows.remove_index (position);
            }

            for (uint i = 0; i < added; i++) {
                Gdk.Monitor monitor = (Gdk.Monitor) monitors.get_item (position + i);
                BlankWindow win = new BlankWindow (monitor);
                win.set_visible (visible);
                blank_windows.insert_val (position + i, win);
            }

            // Set preferred output
            try {
                ximper_shell_notification_center_daemon.set_cc_monitor (
                    ConfigModel.instance.control_center_preferred_output);
                ximper_shell_notification_center_daemon.set_noti_window_monitor (
                    ConfigModel.instance.notification_window_preferred_output);
            } catch (Error e) {
                critical (e.message);
            }
        }

        public void show_blank_windows (Gdk.Monitor ?ref_monitor) {
            if (!use_layer_shell || !ConfigModel.instance.layer_shell_cover_screen) {
                return;
            }
            foreach (unowned BlankWindow win in blank_windows.data) {
                if (win.monitor != ref_monitor) {
                    win.set_visible (true);
                }
            }
        }

        public void hide_blank_windows () {
            if (!use_layer_shell) {
                return;
            }
            foreach (unowned BlankWindow win in blank_windows.data) {
                win.set_visible (false);
            }
        }

        private void reload_blank_windows () {
            if (!use_layer_shell) {
                return;
            }

            foreach (unowned BlankWindow win in blank_windows.data) {
                win.reload_config ();
            }

            if (!control_center.get_visibility ()) {
                return;
            }

            if (ConfigModel.instance.layer_shell_cover_screen) {
                show_blank_windows (null);
            } else {
                hide_blank_windows ();
            }
        }

        private void print_monitors () {
            uint num_monitors = monitors.get_n_items ();
            string monitors_string = "";
            for (uint i = 0; i < num_monitors; i++) {
                Gdk.Monitor ?mon = (Gdk.Monitor) monitors.get_item (i);
                if (mon == null) {
                    continue;
                }
                monitors_string += Functions.monitor_to_string (mon);
            }
            info ("Monitors:\n%s", monitors_string);
        }

        public static int main (string[] args) {
            bool replace = false;
            if (args.length > 0) {
                for (uint i = 1; i < args.length; i++) {
                    string arg = args[i];
                    switch (arg) {
                        case "-s" :
                        case "--style" :
                            style_path = args[++i];
                            break;
                        case "--skip-system-css" :
                            skip_packaged_css = true;
                            break;
                        case "--custom-system-css":
                            custom_packaged_css = args[++i];
                            break;
                        case "-c":
                        case "--config":
                            config_path = args[++i];
                            break;
                        case "--replace":
                            replace = true;
                            break;
                        case "-v":
                        case "--version":
                            stdout.printf ("%s\n", Constants.VERSION);
                            return 0;
                        case "-h":
                        case "--help":
                            print_help (args);
                            return 0;
                        default:
                            print_help (args);
                            return 1;
                    }
                }
            }

            Intl.setlocale (LocaleCategory.ALL, "");
            Intl.bindtextdomain (Constants.GETTEXT_PACKAGE, Constants.LOCALEDIR);
            Intl.bind_textdomain_codeset (Constants.GETTEXT_PACKAGE, "UTF-8");
            Intl.textdomain (Constants.GETTEXT_PACKAGE);

            print_startup_info ();

            // Register custom Widgets so that they can be used in .ui template files
            typeof (AnimatedList).ensure ();
            typeof (AnimatedListItem).ensure ();
            typeof (Underlay).ensure ();

            ConfigModel.init (config_path);

            // Fixes custom themes messing with the default/custom CSS styling
            if (ConfigModel.instance.ignore_gtk_theme) {
                Environment.unset_variable ("GTK_THEME");
            }

            Gtk.init ();
            Adw.init ();

            Functions.init ();
            self_settings = new Settings ("ru.ximperlinux.shell.NotificationCenter");

            app = new NotificationCenter (replace);
            return app.run ();
        }

        private static void print_startup_info () {
            print ("Starting Ximper Shell Notification Center version %s\n", Constants.VERSION);

            // Log distro information
            string info_paths[5] = {
                "/etc/lsb-release",
                "/etc/os-release",
                "/etc/debian_version",
                "/etc/redhat-release",
                "/etc/gentoo-release",
            };
            foreach (unowned string path in info_paths) {
                File ?file = File.new_for_path (path);
                if (file == null) {
                    continue;
                }
                string lines = "";
                try {
                    FileInputStream file_stream = file.read (null);
                    DataInputStream data_stream = new DataInputStream (file_stream);
                    string ?line = null;
                    while ((line = data_stream.read_line (null, null)) != null) {
                        lines += "%s\n".printf (line);
                    }
                } catch (Error e) {
                    continue;
                }
                info ("Contents of %s:\n%s", path, lines);
                break;
            }

            // Log important environment variables
            EnvironmentVariable[] variables = {
                EnvironmentVariable ("XDG_CURRENT_DESKTOP"),
                EnvironmentVariable ("XDG_SESSION_DESKTOP"),
                EnvironmentVariable ("DESKTOP_SESSION"),
                EnvironmentVariable ("XDG_SESSION_TYPE"),
                EnvironmentVariable ("XDG_BACKEND"),
                EnvironmentVariable ("XDG_DATA_HOME"),
                EnvironmentVariable ("XDG_DATA_DIRS"),
                EnvironmentVariable ("SHELL"),
                // From: https://docs.gtk.org/gtk4/running.html
                EnvironmentVariable ("GTK_DEBUG"),
                EnvironmentVariable ("GTK_PATH"),
                EnvironmentVariable ("GTK_IM_MODULE"),
                EnvironmentVariable ("GTK_MEDIA"),
                EnvironmentVariable ("GTK_EXE_PREFIX"),
                EnvironmentVariable ("GTK_DATA_PREFIX"),
                EnvironmentVariable ("GTK_THEME"),
                EnvironmentVariable ("GDK_PIXBUF_MODULE_FILE"),
                EnvironmentVariable ("GDK_DEBUG"),
                EnvironmentVariable ("GSK_DEBUG"),
                EnvironmentVariable ("GDK_BACKEND"),
                EnvironmentVariable ("GDK_DISABLE"),
                EnvironmentVariable ("GDK_GL_DISABLE"),
                EnvironmentVariable ("GDK_VULKAN_DISABLE"),
                EnvironmentVariable ("GDK_WAYLAND_DISABLE"),
                EnvironmentVariable ("GSK_RENDERER"),
                EnvironmentVariable ("GSK_GPU_DISABLE"),
                EnvironmentVariable ("GSK_CACHE_TIMEOUT"),
                EnvironmentVariable ("GTK_CSD"),
                EnvironmentVariable ("GTK_A11Y"),
                EnvironmentVariable ("DESKTOP_STARTUP_ID"),
            };
            string[] envp = Environ.get ();
            string env_variables = "";
            foreach (unowned EnvironmentVariable variable in variables) {
                env_variables += "%s\n".printf (variable.to_string (envp));
            }
            info ("important environment variables:\n%s", env_variables);

            info ("Gtk4LayerShell version: %u.%u.%u",
                  GtkLayerShell.get_major_version (),
                  GtkLayerShell.get_minor_version (),
                  GtkLayerShell.get_micro_version ());
            info ("LayerShell version supported by compositor: %u",
                  GtkLayerShell.get_protocol_version ());
        }

        private static void print_help (string[] args) {
            print ("Usage:\n");
            print ("\t %s <OPTION>\n".printf (args[0]));
            print ("Help:\n");
            print ("\t -h, --help \t\t Show help options\n");
            print ("\t -v, --version \t\t Prints version\n");
            print ("Options:\n");
            print ("\t -s, --style \t\t Use a custom Stylesheet file\n");
            print ("\t -c, --config \t\t Use a custom config file\n");
            print ("\t --skip-system-css \t Skip trying to parse the packaged Stylesheet file."
                   + " Useful for CSS debugging\n");
            print ("\t --custom-system-css \t Pick a custom CSS file to use as the \"system\" CSS."
                   + " Useful for CSS debugging\n");
        }
    }
}
