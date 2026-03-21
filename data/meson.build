# GSchema
compile_schemas = find_program('glib-compile-schemas', required: true)
install_data(
  'ru.ximperlinux.shell.NotificationCenter.gschema.xml',
  install_dir: join_paths(datadir, 'glib-2.0/schemas'),
)

test(
  'Validate schema file',
  compile_schemas,
  args: ['--strict', '--dry-run', meson.current_source_dir()],
)
if get_option('buildtype') != 'release'
  app_resources += custom_target(
    'gschemas',
    input: 'ru.ximperlinux.shell.NotificationCenter.gschema.xml',
    output: 'gschemas.compiled',
    command: [
      compile_schemas,
      '--strict', meson.current_source_dir(),
    ],
  )
  dev_env.set('GSETTINGS_SCHEMA_DIR', meson.current_source_dir())
endif

style_files = []
subdir('style')

blueprints = custom_target(
  'blueprints',
  input: files(run_command('find', '.', '-name', '*.blp').stdout().strip().split('\n')),
  output: '.',
  command: [
    find_program('blueprint-compiler', required: true),
    'batch-compile',
    '@OUTPUT@',
    '@CURRENT_SOURCE_DIR@',
    '@INPUT@',
  ],
  build_always_stale: true,
  build_by_default: true,
)

app_resources += gnome.compile_resources(
  'ximper_shell_notification_center-resources',
  'ximper_shell_notification_center.gresource.xml',
  dependencies: [style_files, blueprints],
  c_name: 'ximper_shell_notification_center',
)
