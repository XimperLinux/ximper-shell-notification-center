complete -f -c ximper-shell-notification-center-client
complete -c ximper-shell-notification-center-client -s h -l help --description "Show help options"
complete -c ximper-shell-notification-center-client -s v -l version --description "Prints version"
complete -c ximper-shell-notification-center-client -s R -l reload-config --description "Reload the config file" -r
complete -c ximper-shell-notification-center-client -s rs -l reload-css --description "Reload the css file. Location change requires restart" -r
complete -c ximper-shell-notification-center-client -s t -l toggle-panel --description "Toggle the notification panel" -r
complete -c ximper-shell-notification-center-client -s op -l open-panel --description "Opens the notification panel" -r
complete -c ximper-shell-notification-center-client -s cp -l close-panel --description "Closes the notification panel" -r
complete -c ximper-shell-notification-center-client -s d -l toggle-dnd --description "Toggle and print the current dnd state" -r
complete -c ximper-shell-notification-center-client -s D -l get-dnd --description "Print the current dnd state" -r
complete -c ximper-shell-notification-center-client -s dn -l dnd-on --description "Turn dnd on and print the new dnd state" -r
complete -c ximper-shell-notification-center-client -s df -l dnd-off --description "Turn dnd off and print the new dnd state" -r
complete -c ximper-shell-notification-center-client -s I -l get-inhibited --description "Print if currently inhibited or not" -r
complete -c ximper-shell-notification-center-client -s In -l get-num-inhibitors --description "Print number of inhibitors" -r
complete -c ximper-shell-notification-center-client -s Ia -l inhibitor-add --description "Add an inhibitor" -r
complete -c ximper-shell-notification-center-client -s Ir -l inhibitor-remove --description "Remove an inhibitor" -r
complete -c ximper-shell-notification-center-client -s Ic -l inhibitors-clear --description "Clears all inhibitors" -r
complete -c ximper-shell-notification-center-client -s c -l count --description "Print the current notification count" -r
complete -c ximper-shell-notification-center-client      -l hide-latest --description "Hides latest notification. Still shown in Control Center" -r
complete -c ximper-shell-notification-center-client      -l hide-all --description "Hides all notifications. Still shown in Control Center" -r
complete -c ximper-shell-notification-center-client      -l close-latest --description "Closes latest notification" -r
complete -c ximper-shell-notification-center-client -s C -l close-all --description "Closes all notifications" -r
complete -c ximper-shell-notification-center-client -s sw -l skip-wait --description "Doesn't wait when ximper-shell-notification-center hasn't been started" -r
complete -c ximper-shell-notification-center-client -s s -l subscribe --description "Subscribe to notification add and close events" -r
complete -c ximper-shell-notification-center-client -s swb -l subscribe-waybar --description "Subscribe to notification add and close events with waybar support. Read README for example" -r
complete -c ximper-shell-notification-center-client      -l change-cc-monitor --description "Changes the preferred control center monitor (resets on config reload)" -r
complete -c ximper-shell-notification-center-client      -l change-noti-monitor --description "Changes the preferred notification monitor (resets on config reload)" -r
