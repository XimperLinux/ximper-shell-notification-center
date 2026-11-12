#!/usr/bin/env bash
set -eu

daemon=$1 client=$2 style=$3 schemas=$4
for program in weston dbus-daemon gdbus; do
    command -v "$program" >/dev/null || exit 77
done
work=$(mktemp -d "${TMPDIR:?}/history-reload.XXXXXXXX")
pids=()
cleanup() {
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
    wait || true
    rm -rf -- "$work"
}
trap cleanup EXIT
export XDG_RUNTIME_DIR="$work" XDG_CACHE_HOME="$work/cache" XDG_CONFIG_HOME="$work/config"
export XDG_STATE_HOME="$work/state" XDG_DATA_HOME="$work/data" XDG_CONFIG_DIRS="$work/etc"
export GSETTINGS_SCHEMA_DIR="$work" GSETTINGS_BACKEND=memory GDK_BACKEND=wayland GSK_RENDERER=cairo
export WAYLAND_DISPLAY=test-display DBUS_SESSION_BUS_ADDRESS="unix:path=$work/bus"
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=$work/no-system-bus"
unset DISPLAY WAYLAND_SOCKET
mkdir -p "$XDG_CONFIG_DIRS/ximper-shell/notification-center"
cp "$style" "$XDG_CONFIG_DIRS/ximper-shell/notification-center/style.css"
glib-compile-schemas --targetdir="$work" "$schemas"
dbus-daemon --session --nofork --address="$DBUS_SESSION_BUS_ADDRESS" &
pids+=("$!")
weston --backend=headless --shell=kiosk-shell.so --socket="$WAYLAND_DISPLAY" --no-config >"$work/weston.log" 2>&1 &
pids+=("$!")
for ((i=0; i<100; i++)); do
    [[ -S "$work/bus" && -S "$work/$WAYLAND_DISPLAY" ]] && break
    sleep 0.05
done
cfg="$work/config.json"
set_limit() {
    printf '{"layer-shell":false,"widgets":["notifications"],"notification-history-limit":%s}\n' "$1" >"$cfg"
}
set_limit 0
"$daemon" --config "$cfg" &
pids+=("$!")
gdbus wait --session --timeout 5 org.freedesktop.Notifications
"$client" --skip-wait --dnd-on
send_one() {
    gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify test 0 '' summary body '[]' '{}' 0 >/dev/null
}
for ((i=0; i<201; i++)); do send_one; done
expected=201
check_rejection() {
    if "$client" --reload-config; then echo 'Invalid reload accepted' >&2; exit 1; fi
    send_one
    expected=$((expected+1))
    [[ $("$client" --skip-wait --count) == "$expected" ]]
}
printf '{' >"$cfg"
check_rejection
for invalid in 4294967297 -1 '"200"' null; do
    set_limit "$invalid"
    check_rejection
done
set_limit 4294967295
"$client" --reload-config
[[ $("$client" --skip-wait --count) == "$expected" ]]
set_limit 2
"$client" --reload-config
[[ $("$client" --skip-wait --count) == 2 ]]
