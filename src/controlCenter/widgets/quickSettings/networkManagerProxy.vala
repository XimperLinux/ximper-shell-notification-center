namespace XimperShellNotificationCenter.Widgets {

    [DBus (name = "org.freedesktop.NetworkManager")]
    public interface NMDBus : Object {
        public abstract bool wireless_enabled { get; set; }
        public abstract ObjectPath[] devices { owned get; }
        public abstract ObjectPath[] active_connections {
            owned get;
        }
    }

    [DBus (name = "org.freedesktop.NetworkManager.Device")]
    public interface NMDeviceDBus : Object {
        public abstract uint device_type { get; }
    }

    [DBus (name = "org.freedesktop.NetworkManager.Device.Wireless")]
    public interface NMWirelessDBus : Object {
        public abstract ObjectPath active_access_point {
            owned get;
        }
        public abstract ObjectPath[] get_all_access_points ()
            throws GLib.Error;
        public abstract void request_scan (
            HashTable<string, Variant> options)
            throws GLib.Error;
    }

    [DBus (name = "org.freedesktop.NetworkManager.AccessPoint")]
    public interface NMAccessPointDBus : Object {
        public abstract uint8[] ssid { owned get; }
        public abstract uint8 strength { get; }
        public abstract uint wpa_flags { get; }
        public abstract uint rsn_flags { get; }
    }

    [DBus (name = "org.freedesktop.NetworkManager.Connection.Active")]
    public interface NMActiveConnDBus : Object {
        public abstract bool vpn { get; }
        public abstract uint state { get; }
        public abstract ObjectPath connection { owned get; }
    }

    [DBus (name = "org.freedesktop.NetworkManager.Settings")]
    public interface NMSettingsDBus : Object {
        public abstract ObjectPath[] list_connections ()
            throws GLib.Error;
    }

    [DBus (name = "org.freedesktop.NetworkManager.Settings.Connection")]
    public interface NMSettingsConnDBus : Object {
        public abstract HashTable<string, HashTable<string, Variant>>
            get_settings () throws GLib.Error;
    }

    public class NetworkManagerProxy : Object {
        public signal void state_changed ();

        private NMDBus ?nm = null;
        private DBusProxy ?nm_raw = null;
        private bool _available = false;
        private bool _has_wifi = false;

        private static NetworkManagerProxy ?_instance = null;

        public static NetworkManagerProxy get_instance () {
            if (_instance == null) {
                _instance = new NetworkManagerProxy ();
            }
            return _instance;
        }

        public bool available {
            get { return _available; }
        }

        public bool has_wifi {
            get { return _has_wifi; }
        }

        private NetworkManagerProxy () {
            connect_dbus.begin ();
        }

        private async void connect_dbus () {
            try {
                nm = yield Bus.get_proxy (BusType.SYSTEM,
                    "org.freedesktop.NetworkManager",
                    "/org/freedesktop/NetworkManager");
                nm_raw = nm as DBusProxy;
                _available = true;

                nm_raw.g_properties_changed.connect (
                    on_props_changed);

                yield detect_wifi ();
            } catch (Error e) {
                warning ("NetworkManager not available: %s",
                         e.message);
            }
        }

        private void on_props_changed (
                Variant changed, string[] invalidated) {
            state_changed ();
        }

        private async void detect_wifi () {
            if (nm == null) return;
            try {
                foreach (var dev_path in nm.devices) {
                    var dev = yield Bus.get_proxy<NMDeviceDBus> (
                        BusType.SYSTEM,
                        "org.freedesktop.NetworkManager",
                        dev_path);
                    if (dev.device_type == 2) {
                        _has_wifi = true;
                        return;
                    }
                }
            } catch (Error e) {
                warning ("Failed to detect WiFi: %s",
                         e.message);
            }
        }

        public bool get_wireless_enabled () {
            if (nm == null) return false;
            return nm.wireless_enabled;
        }

        public void set_wireless_enabled (bool val) {
            if (nm == null) return;
            nm.wireless_enabled = val;
        }

        public async ObjectPath ?get_wifi_device () {
            if (nm == null) return null;
            try {
                foreach (var dev_path in nm.devices) {
                    var dev = yield Bus.get_proxy<NMDeviceDBus> (
                        BusType.SYSTEM,
                        "org.freedesktop.NetworkManager",
                        dev_path);
                    if (dev.device_type == 2) {
                        return dev_path;
                    }
                }
            } catch (Error e) {
                warning ("get_wifi_device: %s", e.message);
            }
            return null;
        }

        public unowned NMDBus ?get_nm () {
            return nm;
        }

        public async Variant ?call_nm (string method,
                                        Variant ?args)
                throws GLib.Error {
            var proxy = yield new DBusProxy.for_bus (
                BusType.SYSTEM,
                DBusProxyFlags.NONE, null,
                "org.freedesktop.NetworkManager",
                "/org/freedesktop/NetworkManager",
                "org.freedesktop.NetworkManager",
                null);
            return yield proxy.call (method, args,
                DBusCallFlags.NONE, 30000, null);
        }

        public static string ssid_to_string (uint8[] ssid) {
            return ((string) ssid).make_valid ();
        }

        public static string get_signal_icon (uint8 strength) {
            if (strength >= 80) {
                return "network-wireless-signal-excellent-symbolic";
            } else if (strength >= 60) {
                return "network-wireless-signal-good-symbolic";
            } else if (strength >= 40) {
                return "network-wireless-signal-ok-symbolic";
            } else if (strength >= 20) {
                return "network-wireless-signal-weak-symbolic";
            }
            return "network-wireless-signal-none-symbolic";
        }
    }
}
