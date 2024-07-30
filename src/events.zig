const std = @import("std");

const c = @import("c.zig");
const Window = @import("Window.zig");

const Events = @This();

var instance: ?Events = null;

window: ?*c.struct_GLFWwindow = null,
resize: ?[2]u32 = null,
mouse_button_pressed_state: [2]bool = [_]bool{false} ** 2,
mouse_button_released_state: [2]bool = [_]bool{false} ** 2,

pub fn init(window: Window) *Events {
    _ = c.glfwSetFramebufferSizeCallback(window.inner, framebufferSizeCallback);
    _ = c.glfwSetMouseButtonCallback(window.inner, mouseButtonCallback);

    instance = .{
        .window = window.inner,
        .resize = null,
        .mouse_button_pressed_state = [_]bool{false} ** 2,
        .mouse_button_released_state = [_]bool{false} ** 2,
    };
    return &instance.?;
}

pub fn reset(self: *Events) void {
    self.resize = null;
    self.mouse_button_pressed_state = [_]bool{false} ** 2;
    self.mouse_button_released_state = [_]bool{false} ** 2;
}

pub fn resized(self: *Events) ?[2]u32 {
    return self.resize;
}

pub fn cursor_pos(self: *Events) ?[2]f32 {
    var x: f64 = undefined;
    var y: f64 = undefined;
    c.glfwGetCursorPos(self.window, &x, &y);
    return .{ @floatCast(x), @floatCast(y) };
}

pub const MouseButton = enum(u32) {
    left = 0,
    right = 1,
};

pub fn mouse_button_pressed(self: *Events, button: MouseButton) bool {
    return c.glfwGetMouseButton(self.window, @intCast(@intFromEnum(button))) == c.GLFW_PRESS;
}

pub fn mouse_button_just_pressed(self: *Events, button: MouseButton) bool {
    return self.mouse_button_pressed_state[@intFromEnum(button)];
}

pub fn mouse_button_just_released(self: *Events, button: MouseButton) bool {
    return self.mouse_button_pressed_state[@intFromEnum(button)];
}

fn framebufferSizeCallback(_: ?*c.struct_GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    if (instance) |*self| {
        self.resize = [_]u32{ @intCast(width), @intCast(height) };
    }
}

fn mouseButtonCallback(_: ?*c.struct_GLFWwindow, button: c_int, action: c_int, _: c_int) callconv(.C) void {
    if (instance) |*self| {
        if (button >= 0 and button < 2) {
            self.mouse_button_pressed_state[@intCast(button)] = action == c.GLFW_PRESS;
            self.mouse_button_released_state[@intCast(button)] = action == c.GLFW_RELEASE;
        }
    }
}
