const std = @import("std");
const raylib_build = @import("raylib");

const title = "action-deckbuilder";

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const do_release = b.option(bool, "do-release", "package for release") orelse false;
    const app_only = b.option(bool, "app-only", "only build the game shared lib") orelse false;
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const native_target = b.standardTargetOptions(.{});
    const targets: []const std.Build.ResolvedTarget = blk: {
        if (do_release and native_target.result.os.tag == .macos) {
            break :blk &.{
                native_target,
                b.resolveTargetQuery(.{
                    .cpu_arch = .x86_64,
                    .os_tag = .windows,
                    .os_version_min = .{ .windows = .win10 },
                    .os_version_max = .{ .windows = .win11_ge },
                    .abi = .gnu,
                }),
            };
        } else {
            if (do_release) {
                std.debug.print("WARNING: Since we're not on macos, only releasing for native target\n", .{});
            }
            break :blk &.{native_target};
        }
    };

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    // Set the release mode if do_release is selected
    if (do_release) {
        b.release_mode = .safe;
    }
    const optimize = if (do_release) std.builtin.OptimizeMode.ReleaseSafe else b.standardOptimizeOption(.{});

    for (targets) |target| {
        const target_triple = target.result.zigTriple(b.allocator) catch "<Failed to get triple>";
        defer b.allocator.free(target_triple);
        std.debug.print("Target triple{s}: {s}\n\n", .{ if (target.query.isNative()) " (native)" else "", target_triple });

        const raylib = try raylib_build.addRaylib(
            b,
            target,
            optimize,
            .{
                .shared = true,
                .config = "-DSUPPORT_CUSTOM_FRAME_CONTROL=1",
            },
        );

        const app_lib = b.addSharedLibrary(.{
            .name = "game",
            // In this case the main source file is merely a path, however, in more
            // complicated build scripts, this could be a generated file.
            .root_source_file = b.path("src/App.zig"),
            .target = target,
            .optimize = optimize,
        });
        app_lib.linkLibrary(raylib);
        app_lib.addIncludePath(b.path("raylib/src"));

        const maybe_exe: ?*std.Build.Step.Compile = if (!app_only) blk: {
            const exe = b.addExecutable(.{
                .name = title,
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
            });
            exe.linkLibrary(raylib);
            exe.addIncludePath(b.path("raylib/src"));
            exe.addLibraryPath(.{ .cwd_relative = "." });

            if (target.query.isNative()) {
                // This *creates* a Run step in the build graph, to be executed when another
                // step is evaluated that depends on it. The next line below will establish
                // such a dependency.
                const run_cmd = b.addRunArtifact(exe);

                // By making the run step depend on the install step, it will be run from the
                // installation directory rather than directly from within the cache directory.
                // This is not necessary, however, if the application depends on other installed
                // files, this ensures they will be present and in the expected location.
                run_cmd.step.dependOn(b.getInstallStep());

                // This allows the user to pass arguments to the application in the build
                // command itself, like this: `zig build run -- arg1 arg2 etc`
                if (b.args) |args| {
                    run_cmd.addArgs(args);
                }

                // This creates a build step. It will be visible in the `zig build --help` menu,
                // and can be selected like this: `zig build run`
                // This will evaluate the `run` step rather than the default, which is "install".
                const run_step = b.step("run", "Run the app");
                run_step.dependOn(&run_cmd.step);
            }
            break :blk exe;
        } else null;

        var artifacts = std.ArrayList(*std.Build.Step.Compile).init(b.allocator);
        defer artifacts.deinit();
        artifacts.append(raylib) catch @panic("Allocation fail");
        artifacts.append(app_lib) catch @panic("Allocation fail");
        if (maybe_exe) |exe| {
            artifacts.append(exe) catch @panic("Allocation fail");
        }

        if (do_release) {
            const install_dir_path = std.fmt.allocPrint(b.allocator, "release/{s}/{s}", .{ target_triple, title }) catch @panic("Allocation fail");
            // NOTE: DONT DO THIS cos the path is needed by build later!
            // defer b.allocator.free(install_dir_path);
            const install_dir = std.Build.InstallDir{ .custom = install_dir_path };
            for (artifacts.items) |artifact| {
                b.getInstallStep().dependOn(&b.addInstallArtifact(artifact, .{
                    .dest_dir = .{ .override = install_dir },
                }).step);
            }
        } else {
            for (artifacts.items) |artifact| {
                b.installArtifact(artifact);
            }
        }

        // Tests
        if (!do_release) {
            const geometry_unit_tests = b.addTest(.{
                .root_source_file = b.path("src/geometry.zig"),
                .target = target,
                .optimize = optimize,
            });

            const run_geometry_unit_tests = b.addRunArtifact(geometry_unit_tests);

            // Similar to creating the run step earlier, this exposes a `test` step to
            // the `zig build --help` menu, providing a way for the user to request
            // running the unit tests.
            const test_step = b.step("test", "Run unit tests");
            //test_step.dependOn(&run_lib_unit_tests.step);
            test_step.dependOn(&run_geometry_unit_tests.step);
        }
    }
}
