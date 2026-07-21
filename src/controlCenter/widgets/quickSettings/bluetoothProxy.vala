namespace XimperShellNotificationCenter.Widgets {

    [DBus (name = "org.bluez.Adapter1")]
    public interface BluezAdapterDBus : Object {
        public abstract bool powered { get; set; }
        public abstract bool discovering { get; }
        public abstract void start_discovery () throws Error;
        public abstract void stop_discovery () throws Error;
        public abstract void remove_device (
            ObjectPath device) throws Error;
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
        bool trusted;
        int battery_percentage;
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
        private uint reload_timeout = 0;

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
            var known_devices =
                new Gee.ArrayList<BluetoothDeviceInfo?> ();
            var discovered_devices =
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

                    Variant ?device_props = null;
                    Variant ?battery_props = null;

                    var iface_iter = ifaces.iterator ();
                    string iface_name;
                    Variant props;
                    while (iface_iter.next ("{s@a{sv}}",
                                            out iface_name,
                                            out props)) {
                        switch (iface_name) {
                            case "org.bluez.Device1":
                                device_props = props;
                                break;
                            case "org.bluez.Battery1":
                                battery_props = props;
                                break;
                        }
                    }

                    if (device_props != null) {
                        var info = parse_device (
                            path, device_props);
                        info.battery_percentage =
                            parse_battery_percentage (
                                battery_props);

                        if (info.paired
                                || info.trusted
                                || info.connected) {
                            known_devices.add (info);
                        } else if (info.name != info.address) {
                            discovered_devices.add (info);
                        }
                    }
                }

                foreach (var info in discovered_devices) {
                    known_devices.add (info);
                }
            } catch (Error e) {
                warning ("load_devices: %s", e.message);
            }

            _devices = known_devices;
            devices_changed ();
        }

        private static int parse_battery_percentage (
                Variant ?props) {
            if (props == null) {
                return -1;
            }

            var prop_iter = props.iterator ();
            string key;
            Variant val;
            while (prop_iter.next ("{sv}", out key, out val)) {
                switch (key) {
                    case "Percentage":
                        return (int) val.get_byte ();
                }
            }

            return -1;
        }

        public static bool is_known_device (
                BluetoothDeviceInfo dev) {
            return dev.paired
                || dev.trusted
                || dev.connected;
        }

        private BluetoothDeviceInfo parse_device (
                string path, Variant props) {
            var info = BluetoothDeviceInfo ();
            info.path = new ObjectPath (path);
            info.battery_percentage = -1;

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
                    case "Trusted":
                        info.trusted = val.get_boolean ();
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

        private void schedule_reload_devices () {
            if (reload_timeout != 0) {
                Source.remove (reload_timeout);
            }
            reload_timeout = Timeout.add (200, () => {
                reload_timeout = 0;
                load_devices.begin ();
                return Source.REMOVE;
            });
        }

        private void on_interfaces_changed (
                DBusConnection conn, string ?sender,
                string path, string iface, string signal,
                Variant params) {
            schedule_reload_devices ();
        }

        private void on_device_props_changed (
                DBusConnection conn, string ?sender,
                string path, string iface, string signal,
                Variant params) {
            if (params.n_children () == 0) return;
            Variant child = params.get_child_value (0);
            if (!child.is_of_type (VariantType.STRING)) {
                return;
            }
            string interface_name = child.get_string ();
            if (interface_name == "org.bluez.Device1"
                    || interface_name == "org.bluez.Battery1") {
                schedule_reload_devices ();
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

        public void forget_device (ObjectPath device_path) {
            if (adapter == null) return;

            try {
                adapter.remove_device (device_path);
                schedule_reload_devices ();
            } catch (Error e) {
                warning ("forget_device: %s", e.message);
            }
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
