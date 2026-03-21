# Ximper Shell Notification Center

A notification daemon with a GTK4/Libadwaita GUI for notifications and the control center.
A component of the Ximper Shell. Fork of [SwayNotificationCenter](https://github.com/ErikReider/SwayNotificationCenter).

*Note: Ximper Shell Notification Center only supports Desktops / Window Managers that
support `wlr_layer_shell_unstable_v1` like Sway or anything wlroots based*

*Note 2: Ximper Shell Notification Center does not support third-party GTK3 themes and is
only tested with the default GTK **Adwaita** theme. Usage of any third-party
theme might require extra tweaks to the default CSS style file*

## Table of Contents

  * [Features](#features)
  * [Available Widgets](#available-widgets)
  * [Build from source](#build-from-source)
  * [Run](#run)
  * [Control Center Shortcuts](#control-center-shortcuts)
  * [Configuring](#configuring)
    * [Toggle Buttons](#toggle-buttons)
  * [Notification Inhibition](#notification-inhibition)
  * [Scripting](#scripting)
     * [Disable scripting](#disable-scripting)
  * [Waybar Example](#waybar-example)
  * [Debugging Environment Variables](#debugging-environment-variables)

## Features

- Grouped notifications
- Keyboard shortcuts
- Notification body markup with image support
- Inline replies
- A panel to view previous notifications
- Show album art for notifications like Spotify
- Do not disturb
- Notification action filtering
- Inhibiting notifications through DBUS or client
- Restores previous Do not disturb value after restart
- Click notification to execute default action
- Show alternative notification actions
- Copy detected 2FA codes to clipboard
- Customization through a CSS file
- Trackpad/mouse gesture to close notification
- The same features as any other basic notification daemon
- Basic configuration through a JSON config file
- Hot-reload config through `ximper-shell-notification-center-client`
- Customizable widgets
- Select the preferred monitor to display on (with ximper-shell-notification-center-client command for scripting)

## Available Widgets

These widgets can be customized, added, removed and even reordered

- Title
- Do Not Disturb
- Notifications (Will always be visible)
- Label
- Mpris (Media player controls for Spotify, Firefox, Chrome, etc...)
- Menubar with dropdown and buttons
- Button grid
- Volume slider using PulseAudio
- Backlight slider

## Build from source

### Dependencies

- `vala >= 0.56`
- `meson`
- `blueprint-compiler`
- `git`
- `scdoc`
- `sassc`
- `gtk4`
- `gtk4-layer-shell`
- `dbus`
- `glib2`
- `gobject-introspection`
- `libgee`
- `json-glib`
- `libadwaita`
- `gvfs`
- `granite7`

#### Optional Dependencies

- `libpulse` (requires meson build options change)
- `libnotify`

```zsh
meson setup build --prefix=/usr
meson compile -C build
meson install -C build
```

## Development

### Setup and build

```sh
meson setup build
meson compile -C build
```

### Set the environment

```sh
# Sets the correct environment variables
meson devenv -C build -w .
# Now you can start nvim, vscode, etc in the development environment
```

## Usage

```ini
# Notification Daemon
exec ximper-shell-notification-center

# Toggle control center
bindsym $mod+Shift+n exec ximper-shell-notification-center-client -t -sw
```

## Run

To start the daemon (remember to kill any other notification daemon before running)

```zsh
./build/src/ximper-shell-notification-center
```

To toggle the panel

```zsh
./build/src/ximper-shell-notification-center-client -t
```

To reload the config

```zsh
./build/src/ximper-shell-notification-center-client -R
```

To reload css after changes

```zsh
./build/src/ximper-shell-notification-center-client -rs
```

## Control Center Shortcuts

- Up/Down: Navigate notifications
- Home: Navigate to the latest notification
- End: Navigate to the oldest notification
- Escape/Caps_Lock: Close notification panel
- Return: Execute default action or close notification if none
- Delete/BackSpace: Close notification
- Shift+C: Close all notifications
- Shift+D: Toggle Do Not Disturb
- Buttons 1-9: Execute alternative actions
- Left click button / actions: Activate notification action
- Middle/Right click notification: Close notification

## Configuring

The main config file is located in `/etc/xdg/ximper-shell/notification-center/config.json`. Copy it over
to your `.config/ximper-shell/notification-center/` folder to customize without needing root access.
See `ximper-shell-notification-center(5)` man page for more information

To reload the config, you'll need to run `ximper-shell-notification-center-client --reload-config`

The main CSS style file is located in `/etc/xdg/ximper-shell/notification-center/style.css`. Copy it over
to your `~/.config/ximper-shell/notification-center/` folder to customize without needing root access. For
more advanced/larger themes, I recommend that you use the SCSS files from source
and customize them instead. To use the SCSS files, compile with `sassc`.

**Tip**: running ximper-shell-notification-center with `GTK_DEBUG=interactive ximper-shell-notification-center` will open a inspector
window that'll allow you to see all of the CSS classes + other information.

## Toggle Buttons

To add toggle buttons to your control center you can set the "type" of any action to "toggle".
The toggle button supports different commands depending on the state of the button and
an "update-command" to update the state in case of changes from outside the notification center. The update-command
is called every time the control center is opened.
The active toggle button also gains the css-class ".toggle:checked"

`config.json` example:

```jsonc
{
  "buttons-grid": { // also works with actions in menubar widget
    "actions": [
      {
        "label": "WiFi",
        "type": "toggle",
        "active": true,
        "command": "sh -c '[[ $XSNC_TOGGLE_STATE == true ]] && nmcli radio wifi on || nmcli radio wifi off'",
        "update-command": "sh -c '[[ $(nmcli radio wifi) == \"enabled\" ]] && echo true || echo false'"
      }
    ]
  }
}
```

## Notification Inhibition

Notifications can be inhibited through the provided `ximper-shell-notification-center-client` executable
or through the DBus interface `ru.ximperlinux.shell.NotificationCenter`.

Here's an example of notification inhibition while screen sharing through
`xdg-desktop-portal-wlr`

```conf
# xdg-desktop-portal-wlr config
[screencast]
exec_before=ximper-shell-notification-center-client --inhibitor-add "xdg-desktop-portal-wlr"
exec_after=ximper-shell-notification-center-client --inhibitor-remove "xdg-desktop-portal-wlr"
```

## Scripting

Scripting rules and logic:

. <b>Only one</b> script can be fired per notification
. Each script requires `exec` and at least one of the other properties
. All listed properties must match the notification for the script to be ran
. If any of the properties doesn't match, the script will be skipped
. If a notification doesn't include one of the properties, that property will
be skipped
· If a script has `run-on` set to `action`, the script will only run when an
action is taken on the notification

More information can be found in the `ximper-shell-notification-center(5)` man page

Notification information can be printed into a terminal by running
`G_MESSAGES_DEBUG=all ximper-shell-notification-center` (when a notification appears).

Config properties:

```jsonc
{
  "scripts": {
    "example-script": {
      "exec": "Your shell command or script here...",
      "app-name": "Notification app-name Regex",
      "summary": "Notification summary Regex",
      "body": "Notification body Regex",
      "urgency": "Low or Normal or Critical",
      "category": "Notification category Regex"
    }
  }
  // other non scripting properties...
}
```

`config.json` example:

```jsonc
{
  "scripts": {
    // This script will only run when Spotify sends a notification containing
    // that exact summary and body
    "example-script": {
      "exec": "/path/to/myRickRollScript.sh",
      "app-name": "Spotify",
      "summary": "Never Gonna Give You Up",
      "body": "Rick Astley - Whenever You Need Somebody"
    }
  }
  // other non scripting properties...
}
```

### Disable scripting

To completely disable scripting, the project needs to be built like so:

```zsh
meson build -Dscripting=false
ninja -C build
meson install -C build
```

## Waybar Example

This example requires a [Nerd Fonts](https://www.nerdfonts.com/) font to get the icons looking right

Waybar config

```json
  "custom/notification": {
    "tooltip": true,
    "format": "<span size='16pt'>{icon}</span>",
    "format-icons": {
      "notification": "󱅫",
      "none": "󰂜",
      "dnd-notification": "󰂠",
      "dnd-none": "󰪓",
      "inhibited-notification": "󰂛",
      "inhibited-none": "󰪑",
      "dnd-inhibited-notification": "󰂛",
      "dnd-inhibited-none": "󰪑"
    },
    "return-type": "json",
    "exec-if": "which ximper-shell-notification-center-client",
    "exec": "ximper-shell-notification-center-client -swb",
    "on-click": "ximper-shell-notification-center-client -t -sw",
    "on-click-right": "ximper-shell-notification-center-client -d -sw",
    "escape": true
  },
```

Waybar css file

```css
#custom-notification {
  font-family: "NotoSansMono Nerd Font";
}
```

Alternatively, the number of notifications can be shown by adding `{0}` anywhere in the `format` field in the Waybar config

```jsonc
  "custom/notification": {
    "format": "{0} {icon}",
    // ...
  },
```

## Debugging Environment Variables

- `G_MESSAGES_DEBUG=all`: Displays all of the debug messages.
- `GTK_DEBUG=interactive`: Opens the GTK Inspector.
- `G_ENABLE_DIAGNOSTIC=1`: If set to a non-zero value, this environment variable
  enables diagnostic messages, like deprecation messages for GObject properties
  and signals.
- `G_DEBUG=fatal_criticals` or `G_DEBUG=fatal_warnings`: Causes GLib to abort
  the program at the first call to g_warning() or g_critical().

More can be read [here](https://www.manpagez.com/html/glib/glib-2.56.0/glib-running.php)
