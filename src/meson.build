# Sets the version to a vala variable in Constants.vala
version = '@0@'.format(meson.project_version())
git = find_program('git', native: true, required: false)
if git.found()
  git_commit = run_command([git, 'rev-parse', '--short', 'HEAD'], check: false)
  git_branch = run_command([git, 'rev-parse', '--abbrev-ref', 'HEAD'], check: false)
  if git_commit.returncode() == 0 and git_branch.returncode() == 0
    version = '@0@ (git-@1@, branch \'@2@\')'.format(
      meson.project_version(),
      git_commit.stdout().strip(),
      git_branch.stdout().strip(),
    )
  endif
endif
version = 'ximper-shell-notification-center @0@'.format(version)
const_config_data = configuration_data()
const_config_data.set_quoted('VERSION', version)
const_config_data.set_quoted('VERSION_NUM', meson.project_version())
const_config_data.set_quoted('GETTEXT_PACKAGE', meson.project_name())
const_config_data.set_quoted('LOCALEDIR', get_option('prefix') / get_option('localedir'))
const_config_data.set_quoted('CONFIG_PATH', join_paths('/', config_path, 'config.json'))
const_config_data.set_quoted('CONFIG_SCHEMA_PATH', join_paths('/', config_path, 'configSchema.json'))
const_config_data.set_quoted('STYLE_PATH', join_paths('/', config_path, 'style.css'))
constants = configure_file(
  input : 'constants.vala.in',
  output : 'constants.vala',
  configuration : const_config_data
)

widget_sources = [
  # Helpers
  'controlCenter/widgets/baseWidget.vala',
  'controlCenter/widgets/factory.vala',
  # Widget: Notifications
  'controlCenter/widgets/notifications/notifications.vala',
  # Widget: MPRIS
  'controlCenter/widgets/mpris/mpris.vala',
  'controlCenter/widgets/mpris/interfaces.vala',
  'controlCenter/widgets/mpris/mpris_player.vala',
  # Widget: Backlight Slider
  'controlCenter/widgets/backlight/backlight.vala',
  'controlCenter/widgets/backlight/backlightUtil.vala',
  # Widget: Inhibitors
  'controlCenter/widgets/inhibitors/inhibitors.vala',
  # Widget: Quick Settings
  'controlCenter/widgets/quickSettings/quickSettings.vala',
  'controlCenter/widgets/quickSettings/quickSettingsTile.vala',
  'controlCenter/widgets/quickSettings/tiles/dndTile.vala',
  'controlCenter/widgets/quickSettings/tiles/darkModeTile.vala',
  'controlCenter/widgets/quickSettings/tiles/powerProfilesTile.vala',
  'controlCenter/widgets/quickSettings/tiles/commandTile.vala',
  'controlCenter/widgets/quickSettings/tiles/caffeineTile.vala',
  'controlCenter/widgets/quickSettings/tiles/nightLightTile.vala',
  'controlCenter/widgets/quickSettings/networkManagerProxy.vala',
  'controlCenter/widgets/quickSettings/bluetoothProxy.vala',
  'controlCenter/widgets/quickSettings/tiles/bluetoothTile.vala',
  'controlCenter/widgets/quickSettings/tiles/wifiTile.vala',
  'controlCenter/widgets/quickSettings/tiles/vpnTile.vala',
]

app_sources = [
  'main.vala',
  'animatedList/animatedList.vala',
  'animatedList/animatedListItem.vala',
  'orderedHashTable/orderedHashTable.vala',
  'iterHelpers/iterBox.vala',
  'iterHelpers/iterListBoxController.vala',
  'underlay/underlay.vala',
  'configModel/configModel.vala',
  'ximperShellNotificationCenterDaemon/ximperShellNotificationCenterDaemon.vala',
  'notiDaemon/notiDaemon.vala',
  'notiModel/notiModel.vala',
  'notificationWindow/notificationWindow.vala',
  'dismissableWidget/dismissableWidget.vala',
  'notification/notification.vala',
  'notificationCloseButton/notificationCloseButton.vala',
  'notificationGroup/notificationGroup.vala',
  'notificationGroup/expandableGroup.vala',
  'controlCenter/controlCenter.vala',
  'controlCenter/controlCenterHeader.vala',
  widget_sources,
  'blankWindow/blankWindow.vala',
  'functions.vala',
  'xdg_activation.vala',
  constants,
]

assert(vala.version() >= '0.56')

app_deps = [
  dependency('gtk4-layer-shell-0', version: '>= 1.0.4'),
  dependency('gio-2.0', version: '>= 2.50'),
  dependency('gio-unix-2.0', version: '>= 2.50'),
  dependency('gtk4', version: '>= 4.16.13'),
  dependency('gtk4-wayland', version: '>= 4.16.5'),
  dependency('json-glib-1.0', version: '>= 1.0'),
  dependency('libadwaita-1', version: '>= 1.6.1'),
  dependency('granite-7', version: '>= 7.5.0'),
  cc.find_library('m', required : true),
  vala.find_library('posix'),
  dependency('gee-0.8', version: '>=0.20.6'),
  dependency('wayland-client', version: '>=1.23.0'),
  protocol_dep,
]

# Checks if the user wants to compile with the PulseAudio dependency
if get_option('pulse-audio')
  add_project_arguments('-D', 'HAVE_PULSE_AUDIO', language: 'vala')
  app_deps += [
    dependency('libpulse'),
    dependency('libpulse-mainloop-glib'),
  ]
  app_sources += [
    # Widget: Volume
    'controlCenter/widgets/volume/volume.vala',
    'controlCenter/widgets/volume/pulseDaemon.vala',
    'controlCenter/widgets/volume/pulseDevice.vala',
    'controlCenter/widgets/volume/pulseSinkInput.vala',
    'controlCenter/widgets/volume/sinkInputRow.vala',
  ]
endif

# Checks if the user wants to compile with DDC/CI support
if get_option('ddc')
  add_project_arguments('-D', 'HAVE_DDC', language: 'vala')
  ddcutil_vapi_dir = meson.current_source_dir() / 'controlCenter' / 'widgets' / 'backlight'
  app_deps += [
    cc.find_library('ddcutil', required: true),
    vala.find_library('ddcutil', dirs: ddcutil_vapi_dir),
  ]
  app_sources += [
    'controlCenter/widgets/backlight/ddcUtil.vala',
  ]
endif

args = [
  '--target-glib=2.82',
]

daemon_exe = executable('ximper-shell-notification-center',
  [ app_sources, app_resources ],
  vala_args: args,
  dependencies: app_deps,
  install: true,
)

client_exe = executable('ximper-shell-notification-center-client',
  ['client.vala', constants],
  vala_args: args,
  dependencies: app_deps,
  install: true,
)

config_data = configuration_data()
config_data.set_quoted('JSONPATH', join_paths('/', config_path, 'configSchema.json'))
config_json = configure_file(
  input : 'config.json.in',
  output : 'config.json',
  configuration : config_data
)

install_data(config_json, install_dir : config_path)
install_data('configSchema.json', install_dir : config_path)

test('Rejected config reload preserves notification history', find_program('bash'),
  args: [files('../tests/history-reload.sh'), daemon_exe, client_exe, style_files[0],
         meson.project_source_root() / 'data'],
  timeout: 60,
)
