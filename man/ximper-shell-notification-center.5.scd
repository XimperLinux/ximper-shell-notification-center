ximper-shell-notification-center(5)

# NAME

ximper-shell-notification-center - Configuration file

# CONFIGURATION

Using a text editor with a JSON language server is recommended when editing the
config file to be able to detect config errors

*ignore-gtk-theme* ++
	type: bool ++
	default: true ++
	description: Unsets the GTK_THEME environment variable, fixing a lot of ++
				 issues with GTK themes ruining the users custom CSS themes.

*positionX* ++
	type: string ++
	default: right ++
	values: left, right, center ++
	description: Horizontal position of control center and notification window

*positionY* ++
	type: string ++
	default: top ++
	values: top, center, bottom ++
	description: Vertical position of control center and notification window

*layer* ++
	type: string ++
	default: overlay ++
	values: background, bottom, top, overlay ++
	description: Layer of notification window relative to normal windows. ++
		background is below all windows, overlay is above all windows.

*layer-shell* ++
	type: bool ++
	default: true ++
	description: Wether or not the windows should be opened as layer-shell ++
		surfaces. Note: Requires ximper-shell-notification-center restart to apply

*control-center-positionX* ++
	type: string ++
	default: right ++
	values: left, right, center ++
	description: Optional: Horizontal position of the control center. ++
		Supersedes positionX if not set to `none`.

*control-center-positionY* ++
	type: string ++
	default: top ++
	values: top, center, bottom ++
	description: Optional: Vertical position of the control center. ++
		Supersedes positionY if not set to `none`.

*control-center-margin-top* ++
	type: integer ++
	default: 0 ++
	description: The margin (in pixels) at the top of the notification center. 0 to disable

*control-center-margin-bottom* ++
	type: integer ++
	default: 0 ++
	description: The margin (in pixels) at the bottom of the notification center. 0 to disable

*control-center-margin-right* ++
	type: integer ++
	default: 0 ++
	description: The margin (in pixels) at the right of the notification center. 0 to disable

*control-center-margin-left* ++
	type: integer ++
	default: 0 ++
	description: The margin (in pixels) at the left of the notification center. 0 to disable

*control-center-layer* ++
	type: string ++
	default: top ++
	values: background, bottom, top, overlay ++
	description: Layer of control center window relative to normal windows. ++
		background is below all windows, overlay is above all windows.

*control-center-exclusive-zone* ++
	type: bool ++
	default: true ++
	description: Whether or not the control center should follow the ++
		compositors exclusive zones. An example would be setting it to ++
		*false* to cover your panel/dock.

*notification-history-limit* ++
	type: integer ++
	default: 200 ++
	description: Maximum number of low and normal urgency notifications kept in ++
		history across all applications. When the limit is exceeded, the oldest ++
		notification is closed first. Updating a notification makes it the newest. ++
		Critical notifications and popup-only notifications do not count toward ++
		the limit. Set to 0 for unlimited history. Reloading the configuration ++
		applies the new limit immediately.

*timeout* ++
	type: integer ++
	default: 10 ++
	description: The notification timeout for notifications with normal priority

*timeout-low* ++
	type: integer ++
	default: 5 ++
	description: The notification timeout for notifications with low priority

*timeout-critical* ++
	type: integer ++
	default: 0 ++
	description: The notification timeout for notifications with critical priority. 0 to disable

*notification-window-width* ++
	type: integer ++
	default: 500 ++
	description: Width of the notification in pixels


*notification-inline-replies* ++
	type: boolean ++
	default: false ++
	description: If notifications should display a text field to reply ++
				 if the sender requests it. NOTE: Replying in popup ++
				 notifications is only available if the compositor ++
				 supports GTK Layer-Shell ON_DEMAND keyboard interactivity.


*notification-window-preferred-output* ++
	type: string ++
	default: "" ++
	description: The preferred output to open the notification window ++
				 (popup notifications). Can either be the monitor connector ++
				 name (ex: "DP-1"), or the full name, manufacturer model serial ++
				 (ex: "Acer Technologies XV272U V 503023B314202"). ++
				 If the output is not found, the currently focused one is picked.


*transition-time* ++
	type: integer ++
	default: 200 ++
	description: The notification animation duration. 0 to disable

*hide-on-clear* ++
	type: bool ++
	default: false ++
	description: Hides the control center after pressing "Clear All"

*hide-on-action* ++
	type: bool ++
	default: true ++
	description: Hides the control center when clicking on notification action


*relative-timestamps* ++
	type: bool ++
	default: true ++
	description: Display notification timestamps relative to now e.g. \"26 minutes ago\". ++
		If false, a local iso8601-formatted absolute timestamp is displayed.

*control-center-height* ++
	type: integer ++
	default: 500 ++
	description: Height of the control center in pixels. ++
		When 'control-center-dynamic-height' is true, ++
		this acts as maximum height. ++
		A value of -1 means that it will fit to the content.

*control-center-dynamic-height* ++
	type: bool ++
	default: true ++
	description: If true, the control center height adjusts ++
		to its content, up to 'control-center-height' as ++
		maximum. If false, height is fixed.

*control-center-width* ++
	type: integer ++
	default: 500 ++
	description: The control center width in pixels

*control-center-preferred-output* ++
	type: string ++
	default: "" ++
	description: The preferred output to open the control center. Can either ++
				 be the monitor connector name (ex: "DP-1"), or ++
				 the full name, manufacturer model serial ++
				 (ex: "Acer Technologies XV272U V 503023B314202"). If the ++
				 output is not found, the currently focused one is picked.

*notification-visibility* ++
	type: object ++
	visibility object properties: ++
		*state*++
			type: string ++
			optional: false ++
			default: enabled ++
			values: ignored, muted, transient, enabled ++
			description: The notification visibility state. ++
		*override-urgency*++
			type: string ++
			optional: true ++
			default: unset ++
			values: unset, low, normal, critical ++
			description: The new urgency for the notification if set.++
		*app-name*++
			type: string ++
			optional: true ++
			description: The app-name. Uses Regex.++
		*desktop-entry*++
			type: string ++
			optional: true ++
			description: The desktop-entry. Uses Regex.++
		*summary*++
			type: string ++
			optional: true ++
			description: The summary of the notification. Uses Regex.++
		*body*++
			type: string ++
			optional: true ++
			description: The body of the notification. Uses Regex.++
		*urgency*++
			type: string ++
			optional: true ++
			default: Normal ++
			values: Low, Normal, Critical ++
			description: The urgency of the notification.++
		*category*++
			type: string ++
			optional: true ++
			description: Which category the notification belongs to. Uses Regex.++
	description: Set the visibility or override urgency of each incoming ++
		notification. ++
		If the notification doesn't include one of the properties, that ++
		property will be ignored. All properties (except for state) use ++
		regex. If all properties match the given notification, the ++
		notification will be follow the provided state. ++
		Only the first matching object will be used. ++
	example:
```
{
	"notification-visibility": {
		"example-name": {
			"state": "The notification state",
			"app-name": "Notification app-name Regex",
			"summary": "Notification summary Regex",
			"body": "Notification body Regex",
			"urgency": "Low or Normal or Critical",
			"category": "Notification category Regex"
		}
	}
}
```

*widgets* ++
	type: array ++
	Default values: ["notifications"] ++
	Valid array values (see *widget-config* for more information): ++
		*notifications*++
			optional: true ++
		*mpris*++
			optional: true ++
		*quick-settings*++
			optional: true ++
#START pulse-audio
		*volume*++
			optional: true ++
#END pulse-audio
		*backlight*++
			optional: true ++
		*inhibitors*++
			optional: true ++
	description: ++
		Which order and which widgets to display. ++
		If the \"notifications\" widget isn't specified, it ++
		will be placed at the bottom. ++
	example:
```
{
	"widgets": [
		"inhibitors",
		"notifications"
	]
}
```

*widget-config* ++
	type: object ++
	description: Configure specific widget properties. ++
	Widgets to customize: ++
		*notifications*++
			type: object ++
			css class: widget-notifications ++
			properties: ++
				show-title: ++
					type: string ++
					optional: true ++
					default: "auto" ++
					enum: auto, true, false ++
					description: Title bar visibility. ++
						auto: show when notifications exist. ++
						true: always visible. ++
						false: hidden, only clear button ++
						shown when notifications exist. ++
			description: The Notifications Widget. ++
		*mpris*++
			type: object ++
			css classes: ++
				widget-mpris ++
				widget-mpris-player ++
				widget-mpris-title ++
				widget-mpris-subtitle ++
			properties: ++
				blacklist: ++
					type: array ++
					optional: true ++
					default: [] ++
					description: Audio sources for the mpris widget to ignore. ++
					Valid array values: ++
						type: string ++
						description: Audio source/app name. Regex allowed. Hint ++
							`$ qdbus | grep mpris` to find source names. ++
				autohide: ++
					type: bool ++
					optional: true ++
					default: false ++
					description: Whether to hide the widget when the ++
								 player has no metadata. ++
				show-album-art: ++
					type: string ++
					optional: true ++
					default: "always" ++
					description: Whether or not the album art should be ++
								 hidden, always visible, or only visible ++
								 when a valid album art is provided. ++
					enum: ["right", "left"] ++
				loop-carousel: ++
					type: bool ++
					optional: true ++
					default: false ++
					description: Whether to loop through the mpris carousel. ++
			description: A widget that displays multiple music players. ++
#START pulse-audio
		*volume*++
			type: object ++
			css class: ++
				widget-volume ++
				per-app-volume ++
			properties: ++
				show-per-app: ++
					type: bool ++
					optional: true ++
					default: false ++
					description: Show per app volume control ++
				show-per-app-icon: ++
					type: bool ++
					optional: true ++
					default: false ++
					description: Show application icon in per app control ++
				show-per-app-label: ++
					type: bool ++
					optional: true ++
					default: false ++
					description: Show application name in per app control ++
				expand-per-app: ++
					type: bool ++
					optional: true ++
					default: false ++
					description: If the per app section should start expanded ++
				empty-list-label: ++
					type: string ++
					optional: true ++
					default: "No active sink input" ++
					description: Text displayed when there are not active sink inputs ++
				expand-button-label: ++
					type: string ++
					optional: true ++
					default: "⇧" ++
					description: Label displayed on button to show per app volume control ++
				collapse-button-label: ++
					type: string ++
					optional: true ++
					default: "⇩" ++
					description: Label displayed on button to hide per app volume control ++
				animation-type: ++
					type: string ++
					optional: true ++
					default: "slide_down" ++
					description: Animation type for the per app volume control ++
					enum: ["slide_down", "slide_up", "none"] ++
				animation-duration: ++
					type: integer ++
					optional: true ++
					default: 250 ++
					description: Duration of animation in milliseconds ++
			description: Slider to control pulse volume ++
#END pulse-audio
		*backlight*++
			type: object ++
			css class: widget-backlight ++
			properties: ++
				min: ++
					type: integer ++
					optional: true ++
					default: 0 ++
					description: Lowest possible value for brightness ++
			description: Unified brightness control widget. Auto-detects display ++
				backlights (/sys/class/backlight), DDC/CI monitors, and keyboard ++
				backlights (/sys/class/leds/*kbd*). ++
		*inhibitors*++
			type: object ++
			css class: widget-inhibitors ++
			properties: ++
				text: ++
					type: string ++
					optional: true ++
					default: "Inhibitors" ++
					description: The title of the widget ++
				clear-all-button: ++
					type: bool ++
					optional: true ++
					default: true ++
					description: Whether to display a "Clear All" button ++
			description: Displayed if notifications are inhibited. ++
		*quick-settings*++
			type: object ++
			css class: widget-quick-settings ++
			properties: ++
				tiles: ++
					type: array ++
					optional: true ++
					description: Array of tile objects. Each tile has a ++
					"type" field and optional type-specific properties. ++
					Tile types: dnd, dark-mode, power-profiles, ++
					caffeine, night-light, command. ++
					night-light accepts "temperature" (int, default 4500). ++
					command accepts "label", "icon", "command", ++
					"update-command", "active". ++
			description: GNOME-style quick settings toggle tiles. ++
	example:
```
{
	"widget-config": {
		"notifications": {
			"show-title": "auto"
		},
		"mpris": {
			"blacklist": ["playerctld"]
		},
		"quick-settings": {
			"tiles": [
				{ "type": "dnd" },
				{ "type": "dark-mode" },
				{ "type": "power-profiles" },
				{ "type": "caffeine" },
				{ "type": "night-light", "temperature": 4500 },
				{ "type": "command", "label": "VPN", "icon": "network-vpn-symbolic", "command": "toggle-vpn.sh" }
			]
		}
	}
}
```
