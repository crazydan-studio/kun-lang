const std = @import("std");

pub fn build(b: *std.Build) void {
    const current = @import("builtin").zig_version;
    if (current.major < 0 or (current.major == 0 and current.minor < 17)) {
        @compileError(std.fmt.comptimePrint("Kun requires Zig >= 0.17.0-dev (detected {})", .{current}));
    }

    const target = b.standardTargetOptions(.{ .default_target = .{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
    } });
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "kun",
        .root_module = exe_mod,
    });

    const lib = b.addLibrary(.{
        .name = "kunlang",
        .root_module = lib_mod,
        .linkage = .dynamic,
    });

    const dump_cmd = b.addExecutable(.{
        .name = "kun",
        .root_module = exe_mod,
    });

    const run_dump = b.addRunArtifact(dump_cmd);
    run_dump.addArg("--dump-ast");
    run_dump.setCwd(b.path("."));

    const dump_step = b.step("dump-ast", "Parse a .kun file and dump its AST");
    if (b.args) |args| {
        run_dump.addArgs(args);
    }
    dump_step.dependOn(&run_dump.step);

    b.installArtifact(exe);
    b.installArtifact(lib);

    const test_exe = b.addTest(.{
        .name = "kun-test",
        .root_module = test_mod,
    });

    const run_test = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test.step);
}
