%define xdg_name ru.ximperlinux.shell.NotificationCenter

Name: ximper-shell-notification-center
Version: 0.2.0
Release: eter1
License: GPL-3.0

Summary: Notification center for Ximper Shell

Group: Graphical desktop/Other

Url: https://gitlab.eterfund.ru/ximperlinux/ximper-shell-notification-center
Vcs: https://gitlab.eterfund.ru/ximperlinux/ximper-shell-notification-center.git

Source: %name-%version.tar

Obsoletes: swaync

BuildRequires(pre): rpm-macros-meson rpm-build-xdg

BuildRequires: meson 
BuildRequires: vala sassc scdoc

BuildRequires: blueprint-compiler

BuildRequires: vapi(granite)
BuildRequires: vapi(gtk4-layer-shell-0)

BuildRequires: pkgconfig(gtk4)
BuildRequires: pkgconfig(gee-0.8)
BuildRequires: pkgconfig(systemd)
BuildRequires: pkgconfig(granite-7)
BuildRequires: pkgconfig(json-glib-1.0)
BuildRequires: pkgconfig(libadwaita-1)
BuildRequires: pkgconfig(gtk4-layer-shell-0)

BuildRequires: pkgconfig(libpulse)
BuildRequires: pkgconfig(ddcutil)

%description
A notification center with a GTK4/Libadwaita GUI for Wayland.
A component of the Ximper Shell.

%prep
%setup

%build
%meson
%meson_build

%install
%meson_install
%find_lang %name

%files -f %name.lang
%_bindir/%name
%_bindir/%name-client

%_datadir/dbus-1/services/%xdg_name.service
%_datadir/dbus-1/services/%xdg_name.cc.service
%_datadir/glib-2.0/schemas/%xdg_name.gschema.xml

%_man1dir/*.1.*
%_man5dir/*.5.*

%dir %_xdgconfigdir/ximper-shell/notification-center
%config %_xdgconfigdir/ximper-shell/notification-center/*

%_datadir/bash-completion/completions/%name
%_datadir/bash-completion/completions/%name-client
%_datadir/zsh/site-functions/_%name
%_datadir/zsh/site-functions/_%name-client
%_datadir/fish/vendor_completions.d/%name.fish
%_datadir/fish/vendor_completions.d/%name-client.fish

%changelog
* Tue May 26 2026 Kirill Unitsaev <fiersik@altlinux.org> 0.2.0-eter1
- Bundle symbolic icon fallbacks
- Fix notification focus handling on niri
- Add notification center metadata description
- Remove unstable dual control center layout

* Sat Mar 21 2026 Kirill Unitsaev <fiersik@altlinux.org> 0.1.0-eter1
- Initial build
