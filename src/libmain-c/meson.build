project('nix-main-c', 'cpp',
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

deps_private_maybe_subproject = [
  dependency('nix-util'),
  dependency('nix-store'),
  dependency('nix-main'),
]
deps_public_maybe_subproject = [
  dependency('nix-util-c'),
  dependency('nix-store-c'),
]
subdir('nix-meson-build-support/subprojects')

add_project_arguments(
  # TODO(Qyriad): Yes this is how the autoconf+Make system did it.
  # It would be nice for our headers to be idempotent instead.

  # From C++ libraries, only for internals
  '-include', 'config-util.hh',
  '-include', 'config-store.hh',

  language : 'cpp',
)

subdir('nix-meson-build-support/common')

sources = files(
  'nix_api_main.cc',
)

include_dirs = [include_directories('.')]

headers = files(
  'nix_api_main.h',
)

subdir('nix-meson-build-support/export-all-symbols')
subdir('nix-meson-build-support/windows-version')

this_library = library(
  'nixmainc',
  sources,
  dependencies : deps_public + deps_private + deps_other,
  include_directories : include_dirs,
  link_args: linker_export_flags,
  prelink : true, # For C++ static initializers
  install : true,
)

install_headers(headers, subdir : 'nix', preserve_path : true)

libraries_private = []

subdir('nix-meson-build-support/export')
