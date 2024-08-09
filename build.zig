const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "clone-it",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    exe.addCSourceFiles(.{ .files = &[_][]const u8{
        "src/stb/stb_image_impl.c",
    } });
    exe.addIncludePath(b.path("src/stb"));

    const glfw_dep = b.dependency("glfw", .{
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(glfw_dep.artifact("glfw"));
    @import("glfw").addPaths(&exe.root_module);

    const zgl_dep = b.dependency("zgl", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zgl", zgl_dep.module("zgl"));

    const zlm_dep = b.dependency("zlm", .{});
    exe.root_module.addImport("zlm", zlm_dep.module("zlm"));

    const zaudio = b.dependency("zaudio", .{});
    exe.root_module.addImport("zaudio", zaudio.module("root"));
    exe.linkLibrary(zaudio.artifact("miniaudio"));

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
