# Ximper Shell Notification Center

Ximper Shell Notification Center is a Wayland notification daemon with a GTK4
panel for notification history, quick settings, media controls, volume,
brightness, inhibitors, and runtime shell controls.

> It is a fork of [SwayNotificationCenter](https://github.com/ErikReider/SwayNotificationCenter).

## Features

- FreeDesktop notification daemon with grouped notification history
- Popup notifications with actions, images, markup, inline replies, and relative timestamps
- GNOME-like control center panel
- Quick settings tiles for Wi-Fi, VPN, Bluetooth, power profiles, DND, dark
  style, night light, and caffeine
- MPRIS media controls with multi-player carousel
- PulseAudio volume control with per-application streams and output selection
- Unified brightness widget for internal displays, DDC/CI monitors, and keyboard backlight
- Notification inhibition through D-Bus and CLI

## Control Center

The control center is built from configurable widgets:

- `backlight` - display, monitor, and keyboard brightness
- `volume` - PulseAudio output and application volume
- `quick-settings` - GNOME-style toggle tiles
- `inhibitors` - active notification inhibitors
- `mpris` - media player controls
- `notifications` - notification history

Default quick settings tiles:

- `wifi`
- `vpn`
- `bluetooth`
- `power-profiles`
- `dnd`
- `dark-mode`
- `night-light`
- `caffeine`

The panel header provides battery status when available, a settings launcher,
lock, and a power menu with actions exposed by logind.

## Requirements

Runtime requirements:

- Wayland compositor with layer-shell support
- GTK4
- GTK4 Layer Shell
- GLib / GObject / GIO
- JSON-GLib
- Libadwaita
- Libgee
- Granite 7
- GVfs

Optional integrations:

- PulseAudio support for the volume widget
- DDC/CI support for external monitor brightness
- NetworkManager for Wi-Fi and VPN tiles
- BlueZ for the Bluetooth tile
- `power-profiles-daemon` for power profiles
- `hyprsunset` for night light
- `tuner` for the settings button

## Build

Build dependencies:

- `meson`
- `ninja`
- `vala >= 0.56`
- `blueprint-compiler`
- `sassc`
- `scdoc`
- `git`

Build and install:

```sh
meson setup build --prefix=/usr
meson compile -C build
meson install -C build
```

Useful build options:

```sh
meson setup build -Dpulse-audio=true -Dddc=true
meson configure build
```

## Run

Start the daemon:

```sh
ximper-shell-notification-center
```

Toggle the control center:

```sh
ximper-shell-notification-center-client --toggle-panel
```

Reload configuration and CSS:

```sh
ximper-shell-notification-center-client --reload-config
ximper-shell-notification-center-client --reload-css
```

Describe the current panel state, resolved paths, capabilities, schema metadata,
and preview information:

```sh
ximper-shell-notification-center-client --describe
```

## Configuration

System defaults are installed to:

```
/etc/xdg/ximper-shell/notification-center/config.json
/etc/xdg/ximper-shell/notification-center/configSchema.json
/etc/xdg/ximper-shell/notification-center/style.css
```

User overrides live in:

```
~/.config/ximper-shell/notification-center/config.json
~/.config/ximper-shell/notification-center/style.css
```

Minimal widget configuration example:

```json
{
  "widgets": [
    "backlight",
    "volume",
    "quick-settings",
    "inhibitors",
    "mpris",
    "notifications"
  ],
  "widget-config": {
    "quick-settings": {
      "tiles": [
        { "type": "wifi" },
        { "type": "vpn" },
        { "type": "bluetooth" },
        { "type": "power-profiles" },
        { "type": "dnd" },
        { "type": "dark-mode" },
        { "type": "night-light" },
        { "type": "caffeine" }
      ]
    }
  }
}
```

## Notification Inhibition

Notifications can be inhibited through the client:

```sh
ximper-shell-notification-center-client --inhibitor-add "screen-share"
ximper-shell-notification-center-client --inhibitor-remove "screen-share"
ximper-shell-notification-center-client --get-inhibited
ximper-shell-notification-center-client --get-num-inhibitors
```

## License

Ximper Shell Notification Center is licensed under the GNU General Public
License v3.0. See [COPYING](COPYING).
