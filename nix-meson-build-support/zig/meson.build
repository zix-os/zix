zig = find_program('zig')
zig_args = [
  '--cache-dir', meson.current_build_dir() / 'zig-cache',
  '--global-cache-dir', meson.project_build_root() / 'zig-cache',
  '-target', (target_machine.cpu_family() + '-' + target_machine.kernel()),
]

if get_option('debug') or get_option('optimization') == 'plain'
  zig_args += ['-O', 'Debug']
elif get_option('optimization') == '2'
  zig_args += ['-O', 'ReleaseFast']
elif get_option('optimization') == '3'
  zig_args += ['-O', 'ReleaseSafe']
elif get_option('optimization') == 's'
  zig_args += ['-O', 'ReleaseSmall']
endif
