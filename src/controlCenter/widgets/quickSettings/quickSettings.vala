namespace XimperShellNotificationCenter.Widgets {
    private struct TileRow {
        Gtk.Box row_box;
        Gtk.Revealer revealer;
        QuickSettingsTile ?active_submenu_tile;
    }

    private static QuickSettingsTile ?create_tile (
            string type_id, Json.Object ?cfg) {
        QuickSettingsTile ?tile = null;

        switch (type_id) {
            case "dnd":
                tile = new DndTile (cfg);
                break;
            case "dark-mode":
                tile = new DarkModeTile (cfg);
                break;
            case "power-profiles":
                tile = new PowerProfilesTile (cfg);
                break;
            case "command":
                tile = new CommandTile (cfg);
                break;
            case "caffeine":
                tile = new CaffeineTile (cfg);
                break;
            case "night-light":
                tile = new NightLightTile (cfg);
                break;
            case "bluetooth":
                tile = new BluetoothTile (cfg);
                break;
            case "wifi":
                tile = new WifiTile (cfg);
                break;
            case "vpn":
                tile = new VpnTile (cfg);
                break;
            default:
                warning ("Unknown quick-settings tile: %s",
                         type_id);
                return null;
        }

        return tile;
    }

    public class QuickSettings : BaseWidget {
        public override string widget_name {
            get {
                return "quick-settings";
            }
        }

        List<QuickSettingsTile> tiles = new List<QuickSettingsTile> ();
        List<Gtk.Widget> grid_children = new List<Gtk.Widget> ();
        TileRow[] rows = {};
        Gtk.SizeGroup ?size_group = null;
        int columns = 2;

        public QuickSettings (string suffix) {
            base (suffix);
            set_orientation (Gtk.Orientation.VERTICAL);

            reload_config ();
        }

        public override void reload_config () {
            clear_grid ();
            tiles = new List<QuickSettingsTile> ();

            Json.Object ?config = get_config (this);
            if (config == null) {
                return;
            }

            Json.Array ?tile_configs = get_prop_array (
                config, "tiles");
            if (tile_configs == null || tile_configs.get_length () == 0) {
                return;
            }

            // Create tiles
            for (uint i = 0; i < tile_configs.get_length (); i++) {
                Json.Object ?tile_cfg =
                    tile_configs.get_object_element (i);
                if (tile_cfg == null) {
                    continue;
                }
                string ?type_id = null;
                if (tile_cfg.has_member ("type")) {
                    type_id = tile_cfg.get_string_member ("type");
                }
                if (type_id == null) {
                    continue;
                }

                QuickSettingsTile ?tile =
                    create_tile (type_id, tile_cfg);
                if (tile == null) {
                    continue;
                }
                connect_tile_signals (tile);

                tiles.append (tile);
            }

            build_grid ();
        }

        private void connect_tile_signals (QuickSettingsTile tile) {
            tile.availability_changed.connect (build_grid);
            tile.submenu_requested.connect (() => {
                int row = find_tile_row (tile);
                if (row >= 0) {
                    on_submenu_requested (tile, row);
                }
            });
            tile.submenu_update_requested.connect (() => {
                int row = find_tile_row (tile);
                if (row >= 0) {
                    update_submenu (tile, row);
                }
            });
        }

        private int find_tile_row (QuickSettingsTile tile) {
            for (int i = 0; i < rows.length; i++) {
                for (var child = rows[i].row_box.get_first_child ();
                     child != null;
                     child = child.get_next_sibling ()) {
                    if (child == tile) return i;
                }
            }
            return -1;
        }

        private void clear_grid () {
            // Unparent tiles from row boxes
            foreach (unowned QuickSettingsTile tile in tiles) {
                if (tile.get_parent () != null) {
                    tile.unparent ();
                }
            }
            // Remove row boxes and revealers
            foreach (unowned Gtk.Widget child in grid_children) {
                remove (child);
            }
            grid_children = new List<Gtk.Widget> ();
            rows = {};
            size_group = null;
        }

        private void build_grid () {
            clear_grid ();

            int row_index = 0;
            size_group = new Gtk.SizeGroup (
                Gtk.SizeGroupMode.VERTICAL);

            // Collect available tiles
            List<unowned QuickSettingsTile> visible_tiles =
                new List<unowned QuickSettingsTile> ();
            foreach (unowned QuickSettingsTile tile in tiles) {
                if (tile.is_available ()) {
                    visible_tiles.append (tile);
                }
            }

            unowned List<unowned QuickSettingsTile> iter =
                visible_tiles;

            while (iter != null) {
                var row_box = new Gtk.Box (
                    Gtk.Orientation.HORIZONTAL, 8);
                row_box.set_homogeneous (true);
                row_box.add_css_class ("quick-settings-row");

                var revealer = new Gtk.Revealer ();
                revealer.set_transition_type (
                    Gtk.RevealerTransitionType.SLIDE_DOWN);
                revealer.set_transition_duration (200);

                rows += TileRow () {
                    row_box = row_box,
                    revealer = revealer,
                    active_submenu_tile = null,
                };

                for (int col = 0; col < columns; col++) {
                    if (iter == null) {
                        var spacer = new Gtk.Box (
                            Gtk.Orientation.HORIZONTAL, 0);
                        row_box.append (spacer);
                        break;
                    }

                    unowned QuickSettingsTile tile = iter.data;
                    size_group.add_widget (tile);
                    row_box.append (tile);
                    iter = iter.next;
                }

                append (row_box);
                append (revealer);
                grid_children.append (row_box);
                grid_children.append (revealer);
                row_index++;
            }
        }

        private void on_submenu_requested (QuickSettingsTile tile,
                                            int row_idx) {
            // Close all other revealers
            for (int i = 0; i < rows.length; i++) {
                if (i != row_idx) {
                    rows[i].revealer.set_reveal_child (false);
                    rows[i].active_submenu_tile = null;
                }
            }

            // Toggle same tile — close
            if (rows[row_idx].active_submenu_tile == tile) {
                rows[row_idx].revealer.set_reveal_child (false);
                rows[row_idx].active_submenu_tile = null;
                return;
            }

            // Open new submenu (always recreate for fresh data)
            Gtk.Widget ?submenu = tile.create_submenu ();
            if (submenu == null) {
                return;
            }

            rows[row_idx].revealer.set_child (submenu);
            rows[row_idx].revealer.set_reveal_child (true);
            rows[row_idx].active_submenu_tile = tile;
        }

        private void update_submenu (QuickSettingsTile tile,
                                     int row_idx) {
            if (rows[row_idx].active_submenu_tile != tile) {
                return;
            }
            Gtk.Widget ?submenu = tile.create_submenu ();
            if (submenu != null) {
                rows[row_idx].revealer.set_child (submenu);
            }
        }

        public override void on_cc_visibility_change (bool val) {
            // Let tiles update their visibility first
            foreach (unowned QuickSettingsTile tile in tiles) {
                tile.on_cc_visibility_change (val);
            }

            if (val) {
                // Rebuild grid with updated visibility
                build_grid ();
            } else {
                // Close all submenus
                for (int i = 0; i < rows.length; i++) {
                    rows[i].revealer.set_reveal_child (false);
                    rows[i].active_submenu_tile = null;
                }
            }
        }
    }
}
