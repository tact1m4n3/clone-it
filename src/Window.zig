const std = @import("std");
const log = std.log.scoped(.window);
const gl = @import("zgl");

const c = @import("c.zig");

const Window = @This();

pub const Settings = struct {
    width: u32,
    height: u32,
    title: [:0]const u8,
};

inner: *c.struct_GLFWwindow,

fn log_glfw_error(code: c_int, description: [*c]const u8) callconv(.C) void {
    log.err("{d}: {s}", .{ code, description });
}

pub fn init(settings: Settings) !Window {
    if (c.glfwInit() == c.GLFW_FALSE) {
        return error.GlfwInitError;
    }
    errdefer _ = c.glfwTerminate();

    _ = c.glfwSetErrorCallback(log_glfw_error);

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 1);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    const inner = c.glfwCreateWindow(@intCast(settings.width), @intCast(settings.height), settings.title, null, null) orelse {
        return error.WindowCreateError;
    };

    c.glfwMakeContextCurrent(inner);

    log.debug("Created glfw window with settings: {any}", .{settings});

    return .{
        .inner = inner,
    };
}

pub fn deinit(window: Window) void {
    c.glfwMakeContextCurrent(null);
    _ = c.glfwDestroyWindow(window.inner);
    _ = c.glfwTerminate();
}

pub fn pollEvents(_: Window) void {
    c.glfwPollEvents();
}

pub fn shouldClose(window: Window) bool {
    return c.glfwWindowShouldClose(window.inner) != 0;
}

pub fn swapBuffers(window: Window) void {
    c.glfwSwapBuffers(window.inner);
}

// pub fn getWindowSize(window: Window) [2]u32 {
//     var width: c_int = undefined;
//     var height: c_int = undefined;
//     c.glfwGetFramebufferSize(window.inner, &width, &height);
//     return .{ @intCast(width), @intCast(height) };
// }
