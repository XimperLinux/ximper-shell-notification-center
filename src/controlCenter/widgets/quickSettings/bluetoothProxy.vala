namespace XimperShellNotificationCenter.Widgets {

    [DBus (name = "org.bluez.Adapter1")]
    public interface BluezAdapterDBus : Object {
        public abstract bool powered { get; set; }
        public abstract bool discovering { get; }
        public abstract void start_discovery () throws Error;
        public abstract void stop_discovery () throws Error;
    }

    [DBus (name = "org.bluez.Device1")]
    public interface BluezDeviceDBus : Object {
        public abstract string address { owned get; }
        public abstract string alias { owned get; }
        public abstract bool connected { get; }
        public abstract bool paired { get; }
        public abstract string icon { owned get; }
        public abstract bool trusted { get; set; }
        public abstract async void connect () throws Error;
        public abstract async void disconnect () throws Error;
    }

    public struct BluetoothDeviceInfo {
        ObjectPath path;
        string name;
        string address;
        string icon_name;
        bool connected;
        bool paired;
    }

    public class BluetoothProxy : Object {
        public signal void state_changed ();
        public signal void devices_changed ();

        private BluezAdapterDBus ?adapter = null;
        private DBusProxy ?adapter_raw = null;
        private ObjectPath ?adapter_path = null;
        private bool _available = false;

        private Gee.ArrayList<BluetoothDeviceInfo?> _devices =
            new Gee.ArrayList<BluetoothDeviceInfo?> ();
        public ObjectPath ?connecting_device = null;

        private DBusConnection ?connection = null;

        private static BluetoothProxy ?_instance = null;

        public static BluetoothProxy get_instance () {
            if (_instance == null) {
                _instance = new BluetoothProxy ();
            }
            return _instance;
        }

        public bool available {
            get { return _available; }
        }

        public bool powered {
            get {
                if (adapter == null) return false;
                return adapter.powered;
            }
        }

        public Gee.ArrayList<BluetoothDeviceInfo?> devices {
            get { return _devices; }
        }

        private BluetoothProxy () {
            connect_dbus.begin ();
        }

        private async void connect_dbus () {
            try {
                connection = yield Bus.get (BusType.SYSTEM);

                // Find adapter via ObjectManager
                var reply = yield connection.call (
                    "org.bluez", "/",
                    "org.freedesktop.DBus.ObjectManager",
                    "GetManagedObjects",
                    null, null,
                    DBusCallFlags.NONE, -1, null);

                var objects = reply.get_child_value (0);
                find_adapter (objects);

                if (adapter_path == null) return;

                adapter = yield Bus.get_proxy (
                    BusType.SYSTEM, "org.bluez",
                    adapter_path);
                adapter_raw = adapter as DBusProxy;
                _available = true;

                adapter_raw.g_properties_changed.connect (
                    on_adapter_props_changed);

                // Watch InterfacesAdded/Removed
                connection.signal_subscribe (
                    "org.bluez",
                    "org.freedesktop.DBus.ObjectManager",
                    "InterfacesAdded", "/", null,
                    DBusSignalFlags.NONE,
                    on_interfaces_changed);

                connection.signal_subscribe (
                    "org.bluez",
                    "org.freedesktop.DBus.ObjectManager",
                    "InterfacesRemoved", "/", null,
                    DBusSignalFlags.NONE,
                    on_interfaces_changed);

                // Watch PropertiesChanged on all bluez objects
                connection.signal_subscribe (
                    "org.bluez",
                    "org.freedesktop.DBus.Properties",
                    "PropertiesChanged", null, null,
                    DBusSignalFlags.NONE,
                    on_device_props_changed);

                yield load_devices ();
            } catch (Error e) {
                debug ("Bluetooth not available: %s",
                       e.message);
            }
        }

        private void find_adapter (Variant objects) {
            var iter = objects.iterator ();
            string path;
            Variant ifaces;
            while (iter.next ("{o@a{sa{sv}}}", out path,
                              out ifaces)) {
                var iface_iter = ifaces.iterator ();
                string iface_name;
                Variant props;
                while (iface_iter.next ("{s@a{sv}}",
                                        out iface_name,
                                        out props)) {
                    if (iface_name == "org.bluez.Adapter1") {
                        adapter_path = new ObjectPath (path);
                        return;
                    }
                }
            }
        }

        private async void load_devices () {
            var new_list =
                new Gee.ArrayList<BluetoothDeviceInfo?> ();

            try {
                var reply = yield connection.call (
                    "org.bluez", "/",
                    "org.freedesktop.DBus.ObjectManager",
                    "GetManagedObjects",
                    null, null,
                    DBusCallFlags.NONE, -1, null);

                var objects = reply.get_child_value (0);
                string adapter_str = (string) adapter_path;

                var iter = objects.iterator ();
                string path;
                Variant ifaces;
                while (iter.next ("{o@a{sa{sv}}}",
                                  out path, out ifaces)) {
                    if (!path.has_prefix (
                            adapter_str + "/dev_")) {
                        continue;
                    }

                    var iface_iter = ifaces.iterator ();
                    string iface_name;
                    Variant props;
                    while (iface_iter.next ("{s@a{sv}}",
                                            out iface_name,
                                            out props)) {
                        if (iface_name
                                != "org.bluez.Device1") {
                            continue;
                        }
                        var info = parse_device (
                            path, props);
                        if (info.paired
                                || info.name != info.address) {
                            new_list.add (info);
                        }
                    }
                }
            } catch (Error e) {
                warning ("load_devices: %s", e.message);
            }

            _devices = new_list;
            devices_changed ();
        }

        private BluetoothDeviceInfo parse_device (
                string path, Variant props) {
            var info = BluetoothDeviceInfo ();
            info.path = new ObjectPath (path);

            var prop_iter = props.iterator ();
            string key;
            Variant val;
            while (prop_iter.next ("{sv}", out key, out val)) {
                switch (key) {
                    case "Alias":
                        info.name = val.get_string ();
                        break;
                    case "Address":
                        info.address = val.get_string ();
                        break;
                    case "Connected":
                        info.connected = val.get_boolean ();
                        break;
                    case "Paired":
                        info.paired = val.get_boolean ();
                        break;
                    case "Icon":
                        info.icon_name = val.get_string ();
                        break;
                }
            }

            if (info.name == null || info.name == "") {
                info.name = info.address ?? "Unknown";
            }

            return info;
        }

        private void on_adapter_props_changed (
                Variant changed, string[] invalidated) {
            state_changed ();
        }

        private void on_interfaces_changed (
                DBusConnection conn, string ?sender,
                string path, string iface, string signal,
                Variant params) {
            load_devices.begin ();
        }

        private void on_device_props_changed (
                DBusConnection conn, string ?sender,
                string path, string iface, string signal,
                Variant params) {
            string iface_name;
            params.get_child (0, "s", out iface_name);
            if (iface_name == "org.bluez.Device1") {
                load_devices.begin ();
            }
        }

        public void set_powered (bool val) {
            if (adapter == null) return;
            adapter.powered = val;
        }

        public void start_discovery () {
            if (adapter == null || !adapter.powered) return;
            if (adapter.discovering) return;
            try {
                adapter.start_discovery ();
            } catch (Error e) {
                debug ("start_discovery: %s", e.message);
            }
        }

        public void stop_discovery () {
            if (adapter == null) return;
            if (!adapter.discovering) return;
            try {
                adapter.stop_discovery ();
            } catch (Error e) {
                debug ("stop_discovery: %s", e.message);
            }
        }

        public async void connect_device (
                ObjectPath device_path) {
            connecting_device = device_path;
            devices_changed ();
            try {
                var dev = yield Bus.get_proxy<BluezDeviceDBus>
                    (BusType.SYSTEM, "org.bluez",
                     device_path);
                var proxy = dev as DBusProxy;
                if (proxy != null) {
                    proxy.set_default_timeout (120000);
                }
                if (!dev.trusted) {
                    dev.trusted = true;
                }
                yield dev.connect ();
            } catch (Error e) {
                warning ("connect_device: %s", e.message);
            }
            connecting_device = null;
            devices_changed ();
        }

        public async void disconnect_device (
                ObjectPath device_path) {
            connecting_device = device_path;
            devices_changed ();
            try {
                var dev = yield Bus.get_proxy<BluezDeviceDBus>
                    (BusType.SYSTEM, "org.bluez",
                     device_path);
                yield dev.disconnect ();
            } catch (Error e) {
                warning ("disconnect_device: %s", e.message);
            }
            connecting_device = null;
            devices_changed ();
        }

        public string ? get_connected_device_name () {
            foreach (var dev in _devices) {
                if (dev.connected) {
                    return dev.name;
                }
            }
            return null;
        }

        public static string get_device_icon (
                string ?icon_class) {
            if (icon_class == null) {
                return "bluetooth-symbolic";
            }
            switch (icon_class) {
                case "audio-headset":
                case "audio-headphones":
                    return "audio-headphones-symbolic";
                case "phone":
                    return "phone-symbolic";
                case "computer":
                    return "computer-symbolic";
                case "input-keyboard":
                    return "input-keyboard-symbolic";
                case "input-mouse":
                    return "input-mouse-symbolic";
                case "input-gaming":
                    return "input-gaming-symbolic";
                default:
                    return "bluetooth-symbolic";
            }
        }
    }
}
