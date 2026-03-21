namespace XimperShellNotificationCenter.Widgets {

    public struct DdcDisplayInfo {
        int dispno;
        string model_name;
    }

    class DdcUtil {
        const uint8 VCP_BRIGHTNESS = 0x10;

        void* handle = null;
        string display_name = "DDC Display";

        static bool lib_initialized = false;

        uint poll_source = 0;

        public signal void brightness_change (int percent);

        public DdcUtil (int display_number) {
            if (!init_library ()) return;
            open_display (display_number);
        }

        private static bool init_library () {
            if (lib_initialized) return true;

            string[]? msgs;
            int rc = Ddcutil.init2 (
                null,
                Ddcutil.SyslogLevel.NEVER,
                Ddcutil.InitOptions.DISABLE_CONFIG_FILE,
                out msgs);

            if (rc != 0) {
                warning ("ddcutil init failed: %d", rc);
                return false;
            }
            lib_initialized = true;
            return true;
        }

        public static DdcDisplayInfo[] detect_displays () {
            if (!init_library ()) return {};

            Ddcutil.DisplayInfoList? dlist;
            int rc = Ddcutil.get_display_info_list2 (false, out dlist);
            if (rc != 0 || dlist == null || dlist.ct == 0) {
                return {};
            }

            DdcDisplayInfo[] result = {};
            for (int i = 0; i < dlist.ct; i++) {
                result += DdcDisplayInfo () {
                    dispno = dlist.info[i].dispno,
                    model_name = ((string) dlist.info[i].model_name).dup (),
                };
            }
            return result;
        }

        private void open_display (int display_number) {
            Ddcutil.DisplayInfoList? dlist;
            int rc = Ddcutil.get_display_info_list2 (false, out dlist);
            if (rc != 0 || dlist == null || dlist.ct == 0) {
                warning ("No DDC displays found");
                brightness_change (-1);
                return;
            }

            int idx = 0;
            if (display_number > 0) {
                bool found = false;
                for (int i = 0; i < dlist.ct; i++) {
                    if (dlist.info[i].dispno == display_number) {
                        idx = i;
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    warning ("DDC display %d not found, using first", display_number);
                }
            }

            display_name = ((string) dlist.info[idx].model_name).dup ();

            void* dh;
            rc = Ddcutil.open_display2 (dlist.info[idx].dref, true, out dh);
            if (rc != 0) {
                warning ("Failed to open DDC display: %d", rc);
                brightness_change (-1);
                return;
            }
            handle = dh;
        }

        public void start () {
            get_brightness ();
            start_polling ();
        }

        public void close () {
            stop_polling ();
        }

        private void start_polling () {
            stop_polling ();
            poll_source = Timeout.add_seconds (5, () => {
                get_brightness ();
                return Source.CONTINUE;
            });
        }

        private void stop_polling () {
            if (poll_source != 0) {
                Source.remove (poll_source);
                poll_source = 0;
            }
        }

        private void get_brightness () {
            if (handle == null) {
                brightness_change (-1);
                return;
            }

            Ddcutil.NonTableVcpValue val;
            int rc = Ddcutil.get_non_table_vcp_value (handle, VCP_BRIGHTNESS, out val);

            if (rc != 0) {
                warning ("Failed to read DDC brightness: %d", rc);
                return;
            }

            int current = (val.sh << 8) | val.sl;
            int max = (val.mh << 8) | val.ml;

            if (max == 0) {
                brightness_change (-1);
                return;
            }

            int percent = (int) Math.round (current * 100.0 / max);
            brightness_change (percent);
        }

        public async void set_brightness (float percent) {
            if (handle == null) return;

            int value = (int) Math.round (percent);
            if (value < 0) value = 0;
            if (value > 100) value = 100;

            int rc = Ddcutil.set_non_table_vcp_value (handle, VCP_BRIGHTNESS, 0, (uint8) value);

            if (rc != 0) {
                warning ("Failed to set DDC brightness: %d", rc);
            }
        }

        public string get_display_name () {
            return display_name;
        }

        ~DdcUtil () {
            stop_polling ();
            if (handle != null) {
                Ddcutil.close_display (handle);
                handle = null;
            }
        }
    }
}
