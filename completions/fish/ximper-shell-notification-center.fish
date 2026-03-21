complete -f -c ximper-shell-notification-center
complete -c ximper-shell-notification-center -s h -l help --description "Show help options"
complete -c ximper-shell-notification-center -s v -l version --description "Prints version"
complete -c ximper-shell-notification-center -s s -l style --description "Use a custom Stylesheet file" -r
complete -c ximper-shell-notification-center -s c -l config --description "Use a custom config file" -r
complete -c ximper-shell-notification-center      -l replace --description "Replace the currently running instance of XimperShellNotificationCenter"
complete -c ximper-shell-notification-center      -l skip-system-css --description "Skip trying to parse the packaged Stylesheet file. Useful for CSS debugging"
complete -c ximper-shell-notification-center      -l custom-system-css --description "Pick a custom CSS file to use as the \"system\" CSS. Useful for CSS debugging" -r
