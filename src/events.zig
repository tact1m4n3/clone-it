const std = @import("std");

const c = @import("c.zig");
const Window = @import("Window.zig");

const Registry = struct {
    window: ?*c.struct_GLFWwindow = null,
    resize: ?[2]u32 = null,
    keys: [10]bool = [_]bool{false} ** 10,
    mouse_buttons: [2]bool = [_]bool{false} ** 2,
};

var registry: Registry = .{};

pub fn init(window: Window) void {
    registry.window = window.inner;

    _ = c.glfwSetFramebufferSizeCallback(window.inner, framebufferSizeCallback);
}

pub fn reset() void {
    registry.resize = null;
}

pub fn resized() ?[2]u32 {
    return registry.resize;
}

pub fn cursor_pos() ?[2]f32 {
    var x: f64 = undefined;
    var y: f64 = undefined;
    c.glfwGetCursorPos(registry.window, &x, &y);
    return .{ @floatCast(x), @floatCast(y) };
}

pub const Key = enum(u32) {
    key0 = 48,
    key1 = 49,
    key2 = 50,
    key3 = 51,
    key4 = 52,
    key5 = 53,
    key6 = 54,
    key7 = 55,
    key8 = 56,
    key9 = 57,
};

pub fn key_pressed(key: Key) bool {
    return c.glfwGetKey(registry.window, @intFromEnum(key)) == c.GLFW_PRESS;
}

pub fn key_just_pressed(key: Key) bool {
    return registry.keys[@intFromEnum(key) - @intFromEnum(.key0)];
}

pub const MouseButton = enum(u32) {
    left = 0,
    right = 1,
};

pub fn mouse_button_pressed(button: MouseButton) bool {
    return c.glfwGetMouseButton(registry.window, @intFromEnum(button)) == c.GLFW_PRESS;
}

fn framebufferSizeCallback(_: ?*c.struct_GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    registry.resize = [_]u32{ @intCast(width), @intCast(height) };
}
