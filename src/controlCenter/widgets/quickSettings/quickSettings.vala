namespace XimperShellNotificationCenter.Widgets {
    private struct TileRow {
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
            default:
                warning ("Unknown quick-settings tile: %s",
                         type_id);
                return null;
        }

        if (!tile.is_available ()) {
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
        TileRow[] rows = {};
        int columns = 2;

        public QuickSettings (string suffix) {
            base (suffix);
            set_orientation (Gtk.Orientation.VERTICAL);

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
                string ?type_id =
                    tile_cfg.get_string_member_with_default (
                        "type", null);
                if (type_id == null) {
                    continue;
                }

                QuickSettingsTile ?tile =
                    create_tile (type_id, tile_cfg);
                if (tile == null) {
                    continue;
                }

                tiles.append (tile);
            }

            build_grid ();
        }

        private void build_grid () {
            int row_index = 0;
            unowned List<QuickSettingsTile> iter = tiles;
            var size_group = new Gtk.SizeGroup (
                Gtk.SizeGroupMode.VERTICAL);

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
                    revealer = revealer,
                    active_submenu_tile = null,
                };

                int current_row = row_index;

                for (int col = 0; col < columns; col++) {
                    if (iter == null) {
                        // Pad with empty box for alignment
                        var spacer = new Gtk.Box (
                            Gtk.Orientation.HORIZONTAL, 0);
                        row_box.append (spacer);
                        break;
                    }

                    unowned QuickSettingsTile tile = iter.data;
                    size_group.add_widget (tile);
                    row_box.append (tile);

                    // Connect submenu signals
                    tile.submenu_requested.connect (() => {
                        on_submenu_requested (tile, current_row);
                    });
                    tile.submenu_update_requested.connect (() => {
                        update_submenu (tile, current_row);
                    });

                    iter = iter.next;
                }

                append (row_box);
                append (revealer);
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
            if (!val) {
                // Close all submenus
                for (int i = 0; i < rows.length; i++) {
                    rows[i].revealer.set_reveal_child (false);
                    rows[i].active_submenu_tile = null;
                }
            }

            foreach (unowned QuickSettingsTile tile in tiles) {
                tile.on_cc_visibility_change (val);
            }
        }
    }
}
