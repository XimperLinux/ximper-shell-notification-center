namespace XimperShellNotificationCenter.Widgets {
    public abstract class QuickSettingsTile : Gtk.Box {
        protected Gtk.Button toggle_button;
        protected Gtk.Image icon;
        protected Gtk.Label title_label;
        protected Gtk.Label subtitle_label;
        protected Gtk.Button ?arrow_button = null;

        private bool _active = false;
        public bool active {
            get { return _active; }
            set {
                _active = value;
                if (_active) {
                    add_css_class ("active");
                } else {
                    remove_css_class ("active");
                }
            }
        }

        public signal void submenu_requested ();
        public signal void submenu_update_requested ();

        protected QuickSettingsTile (string icon_name,
                                     string title,
                                     string ?subtitle = null) {
            Object (orientation: Gtk.Orientation.HORIZONTAL);
            set_hexpand (true);
            set_valign (Gtk.Align.FILL);
            add_css_class ("quick-settings-tile");

            // Toggle button — main clickable area
            toggle_button = new Gtk.Button ();
            toggle_button.add_css_class ("tile-toggle");
            toggle_button.set_hexpand (true);

            var btn_content = new Gtk.Box (
                Gtk.Orientation.HORIZONTAL, 8);
            btn_content.set_valign (Gtk.Align.CENTER);

            icon = new Gtk.Image.from_icon_name (icon_name);
            icon.add_css_class ("tile-icon");

            var text_box = new Gtk.Box (
                Gtk.Orientation.VERTICAL, 0);
            text_box.set_valign (Gtk.Align.CENTER);
            text_box.set_halign (Gtk.Align.START);

            title_label = new Gtk.Label (title);
            title_label.set_halign (Gtk.Align.START);
            title_label.set_ellipsize (Pango.EllipsizeMode.END);
            title_label.add_css_class ("tile-title");

            subtitle_label = new Gtk.Label (subtitle);
            subtitle_label.set_halign (Gtk.Align.START);
            subtitle_label.set_ellipsize (Pango.EllipsizeMode.END);
            subtitle_label.add_css_class ("tile-subtitle");
            subtitle_label.add_css_class ("dim-label");
            subtitle_label.add_css_class ("caption");
            subtitle_label.set_visible (subtitle != null);

            text_box.append (title_label);
            text_box.append (subtitle_label);

            btn_content.append (icon);
            btn_content.append (text_box);
            toggle_button.set_child (btn_content);

            toggle_button.clicked.connect (() => {
                on_toggle ();
            });

            append (toggle_button);
        }

        protected void setup_arrow () {
            add_css_class ("has-submenu");
            var separator = new Gtk.Separator (
                Gtk.Orientation.VERTICAL);
            separator.add_css_class ("tile-separator");

            arrow_button = new Gtk.Button ();
            arrow_button.add_css_class ("tile-arrow");
            arrow_button.set_child (
                new Gtk.Image.from_icon_name (
                    "pan-end-symbolic"));

            arrow_button.clicked.connect (() => {
                submenu_requested ();
            });

            append (separator);
            append (arrow_button);
        }

        public void set_subtitle (string ?text) {
            if (text != null) {
                subtitle_label.set_text (text);
                subtitle_label.set_visible (true);
            } else {
                subtitle_label.set_visible (false);
            }
        }

        public virtual bool is_available () {
            return true;
        }

        public abstract void on_toggle ();

        public virtual Gtk.Widget ?create_submenu () {
            return null;
        }

        public virtual void on_cc_visibility_change (bool visible) {
        }

        protected void build_submenu_header (
                Gtk.Box submenu_box,
                Gtk.Button ?action_button = null) {
            var header = new Gtk.Box (
                Gtk.Orientation.HORIZONTAL, 8);
            header.add_css_class ("submenu-header");

            var header_icon =
                new Gtk.Image.from_icon_name (
                    icon.icon_name);
            header_icon.set_valign (Gtk.Align.CENTER);
            header_icon.add_css_class (
                "submenu-header-icon");
            var header_label =
                new Gtk.Label (title_label.get_text ());
            header_label.add_css_class (
                "submenu-header-label");
            header_label.set_hexpand (true);
            header_label.set_halign (Gtk.Align.START);

            header.append (header_icon);
            header.append (header_label);

            if (action_button != null) {
                action_button.add_css_class ("flat");
                action_button.add_css_class ("circular");
                header.append (action_button);
            }

            submenu_box.prepend (header);
        }

        protected void clear_submenu_content (
                Gtk.Box submenu_box) {
            for (var child =
                     submenu_box.get_first_child ();
                 child != null;) {
                var next = child.get_next_sibling ();
                if (!child.has_css_class (
                        "submenu-header")) {
                    submenu_box.remove (child);
                }
                child = next;
            }
        }
    }
}
