const std = @import("std");
const zig = @import("zig");

pub fn createCompilation(
    gpa_allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    lib_dir: []const u8,
    global_cache_dir: []const u8,
) !*zig.Compilation {
    var zig_lib_directory: zig.Compilation.Directory = .{
        .path = lib_dir,
        .handle = try std.fs.openDirAbsolute(lib_dir, .{}),
    };
    defer zig_lib_directory.handle.close();

    var zig_global_cache_directory: zig.Compilation.Directory = .{
        .path = global_cache_dir,
        .handle = try std.fs.openDirAbsolute(global_cache_dir, .{}),
    };
    defer zig_global_cache_directory.handle.close();

    const local_cache_dir = "zig-cache";
    var zig_local_cache_directory: zig.Compilation.Directory = .{
        .path = local_cache_dir,
        .handle = try std.fs.cwd().openDir(local_cache_dir, .{}),
    };
    defer zig_local_cache_directory.handle.close();

    var thread_pool: std.Thread.Pool = undefined;
    try thread_pool.init(.{
        .allocator = gpa_allocator,
    });
    defer thread_pool.deinit();

    const target = .{
        .cpu_arch = std.Target.Cpu.Arch.x86_64,
        .os_tag = std.Target.Os.Tag.linux,
        .abi = std.Target.Abi.musl,
    };

    const resolved_target = .{
        .result = try std.zig.system.resolveTargetQuery(target),
        .is_native_os = true,
        .is_native_abi = true,
    };

    const resolved_options = try zig.Compilation.Config.resolve(.{
        .output_mode = std.builtin.OutputMode.Exe,
        .link_mode = .Static,
        .resolved_target = resolved_target,
        .is_test = false,
        .have_zcu = true,
        .emit_bin = true,
        .root_optimize_mode = std.builtin.OptimizeMode.Debug,
        .root_strip = false,
        .link_libc = false,
        .any_unwind_tables = false,
    });

    const root_module = try zig.Package.Module.create(arena_allocator, .{
        .global_cache_directory = zig_global_cache_directory,
        .paths = .{
            .root = zig.Package.Path.cwd(),
            .root_src_path = "flake.zig",
        },
        .fully_qualified_name = "root",
        .cc_argv = &.{},
        .inherited = .{
            .resolved_target = resolved_target,
        },
        .global = resolved_options,
        .parent = null,
        .builtin_mod = null,
    });

    const comp = try zig.Compilation.create(gpa_allocator, arena_allocator, .{
        .zig_lib_directory = zig_lib_directory,
        .local_cache_directory = zig_local_cache_directory,
        .global_cache_directory = zig_global_cache_directory,
        .thread_pool = &thread_pool,
        .self_exe_path = "zig",
        .config = resolved_options,
        .root_name = "root",
        .sysroot = null,
        .main_mod = root_module,
        .root_mod = root_module,
        .std_mod = null,
        .emit_bin = null,
        .emit_h = null,
        .emit_asm = null,
        .emit_llvm_ir = null,
        .emit_llvm_bc = null,
        .emit_docs = null,
        .emit_implib = null,
        .lib_dirs = &.{},
        .rpath_list = &.{},
        .symbol_wrap_set = .{},
        .c_source_files = &.{},
        .rc_source_files = &.{},
        .manifest_file = null,
        .link_objects = &.{},
        .framework_dirs = &.{},
        .frameworks = &.{},
        .system_lib_names = &.{},
        .system_lib_infos = &.{},
        .wasi_emulated_libs = &.{},
        .want_compiler_rt = false,
        .hash_style = .gnu,
        .linker_script = null,
        .version_script = null,
        .linker_allow_undefined_version = false,
        .disable_c_depfile = false,
        .native_system_include_paths = &.{},
        .global_cc_argv = &.{},
    });

    return comp;
}
