project('nix-cmd', 'cpp', 'c',
  version : files('.zix-version'),
  default_options : [
    'cpp_std=c++2a',
    # TODO(Qyriad): increase the warning level
    'warning_level=1',
    'errorlogs=true', # Please print logs for tests that fail
  ],
  meson_version : '>= 1.1',
  license : 'LGPL-2.1-or-later',
)

fs = import('fs')

cxx = meson.get_compiler('cpp')

subdir('nix-meson-build-support/deps-lists')

configdata = configuration_data()

deps_private_maybe_subproject = [
]
deps_public_maybe_subproject = [
  dependency('nix-util'),
  dependency('nix-store'),
  dependency('nix-fetchers'),
  dependency('nix-expr'),
  dependency('nix-flake'),
  dependency('nix-main'),
]
subdir('nix-meson-build-support/subprojects')

nlohmann_json = dependency('nlohmann_json', version : '>= 3.9')
deps_public += nlohmann_json

lowdown = dependency('lowdown', version : '>= 0.9.0', required : get_option('markdown'))
deps_private += lowdown
configdata.set('HAVE_LOWDOWN', lowdown.found().to_int())
# The API changed slightly around terminal initialization.
configdata.set('HAVE_LOWDOWN_1_4', lowdown.version().version_compare('>= 1.4.0').to_int())

config_h = configure_file(
  configuration : configdata,
  output : 'config-cmd.hh',
)

add_project_arguments(
  # TODO(Qyriad): Yes this is how the autoconf+Make system did it.
  # It would be nice for our headers to be idempotent instead.
  '-include', 'config-util.hh',
  '-include', 'config-store.hh',
  '-include', 'config-expr.hh',
  '-include', 'config-cmd.hh',
  language : 'cpp',
)

subdir('nix-meson-build-support/common')

sources = files(
  'built-path.cc',
  'command-installable-value.cc',
  'command.cc',
  'common-eval-args.cc',
  'editor-for.cc',
  'installable-attr-path.cc',
  'installable-derived-path.cc',
  'installable-flake.cc',
  'installable-value.cc',
  'installables.cc',
  'legacy.cc',
  'markdown.cc',
  'misc-store-flags.cc',
  'network-proxy.cc',
  'repl-interacter.cc',
  'repl.cc',
)

include_dirs = [include_directories('.')]

headers = files(
  'built-path.hh',
  'command-installable-value.hh',
  'command.hh',
  'common-eval-args.hh',
  'compatibility-settings.hh',
  'editor-for.hh',
  'installable-attr-path.hh',
  'installable-derived-path.hh',
  'installable-flake.hh',
  'installable-value.hh',
  'installables.hh',
  'legacy.hh',
  'markdown.hh',
  'misc-store-flags.hh',
  'network-proxy.hh',
  'repl-interacter.hh',
  'repl.hh',
)

subdir('nix-meson-build-support/zig')

sources += custom_target(
  'zig build-obj',
  command: [zig, 'build-lib', '-femit-h=@OUTDIR@/libcmd-zig.h', '-femit-bin=@OUTPUT@', '-ofmt=c', '-lc', zig_args, '@INPUT@'],
  output: 'libcmd-zig.c',
  input: 'libcmd.zig',
  depend_files: [
    'repl.zig',
  ],
)

include_dirs += fs.parent(fs.parent(zig.full_path())) / 'lib' / 'zig'

this_library = library(
  'nixcmd',
  sources,
  config_h,
  dependencies : deps_public + deps_private + deps_other,
  include_directories : include_dirs,
  prelink : true, # For C++ static initializers
  install : true,
)

install_headers(headers, subdir : 'nix', preserve_path : true)

libraries_private = []

subdir('nix-meson-build-support/export')
