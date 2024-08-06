const std = @import("std");
const c = @import("c.zig");
const gl = @import("zgl");
const zlm = @import("zlm");

const World = @import("World.zig");

const glfw = c.glfw;
const stbi = c.stbi;

const zlm_f64 = zlm.SpecializeOn(f64);

pub const AppData = struct {
    screen: struct {
        width: usize,
        height: usize,
        aspect_ratio: gl.Float,
    },
    mouse: struct {
        position: zlm_f64.Vec2,
        left_down: ?struct {
            down: zlm_f64.Vec2,
            is_event: bool, // TODO: Rename this field
        },
        right_down: ?struct {
            down: zlm_f64.Vec2,
            is_event: bool, // TODO: Rename this field
        },
        scroll: ?struct {
            y_offset: f64,
        },
    },
    key: struct {
        is_shift: bool,
    },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    if (glfw.glfwInit() == glfw.GLFW_FALSE) {
        @panic("TODO: Handle error!");
    }
    defer glfw.glfwTerminate();

    var app_data = AppData{
        .screen = undefined,
        .mouse = .{
            .position = undefined,
            .left_down = null,
            .right_down = null,
            .scroll = null,
        },
        .key = .{
            .is_shift = false,
        },
    };

    glfw.glfwWindowHint(glfw.GLFW_VERSION_MAJOR, 4);
    glfw.glfwWindowHint(glfw.GLFW_VERSION_MINOR, 1);

    const window = glfw.glfwCreateWindow(600, 400, "TODO: Add a title", null, null) orelse @panic("TODO: Handle error!");
    defer glfw.glfwDestroyWindow(window);

    glfw.glfwSetWindowUserPointer(window, &app_data);

    _ = glfw.glfwSetFramebufferSizeCallback(window, onFramebufferSize);
    _ = glfw.glfwSetMouseButtonCallback(window, onMouseButton);
    _ = glfw.glfwSetScrollCallback(window, onScroll);

    glfw.glfwMakeContextCurrent(window);

    glfw.glfwSwapInterval(1);

    try gl.loadExtensions(.{}, struct {
        pub fn getProcAddress(_: @TypeOf(.{}), procname: [:0]const u8) ?gl.binding.FunctionPointer {
            return glfw.glfwGetProcAddress(procname) orelse struct {
                pub fn procNotFound() callconv(.C) noreturn {
                    @panic("Unsupported OpenGL function");
                }
            }.procNotFound;
        }
    }.getProcAddress);

    glfw.glfwMaximizeWindow(window);

    gl.enable(.cull_face);
    gl.enable(.depth_test);
    gl.depthFunc(.less_or_equal);
    gl.enable(.blend);
    gl.blendFunc(.src_alpha, .one_minus_src_alpha);

    gl.clearColor(0.0, 1.0, 1.0, 1.0);

    var world = try World.init(allocator);
    defer world.deinit();

    world.grid_renderer.uploadData();
    world.blocks_renderer.uploadBlockAtlas();
    world.blocks_renderer.uploadData();

    while (glfw.glfwWindowShouldClose(window) == glfw.GLFW_FALSE) {
        glfw.glfwPollEvents();

        // Update
        {
            {
                // TODO: Ensure no DPI scaling has to be done
                var xpos: f64 = undefined;
                var ypos: f64 = undefined;

                glfw.glfwGetCursorPos(window, &xpos, &ypos);

                app_data.mouse.position = .{ .x = xpos, .y = ypos };
            }

            if (glfw.glfwGetKey(window, glfw.GLFW_KEY_ESCAPE) != glfw.GLFW_RELEASE) {
                glfw.glfwSetWindowShouldClose(window, glfw.GLFW_TRUE);
            }

            // TODO: Also check for modifiers potentially
            app_data.key.is_shift = glfw.glfwGetKey(window, glfw.GLFW_KEY_LEFT_SHIFT) != glfw.GLFW_RELEASE or glfw.glfwGetKey(window, glfw.GLFW_KEY_RIGHT_SHIFT) != glfw.GLFW_RELEASE;

            world.update(app_data);
            world.grid_renderer.update(app_data);
            world.blocks_renderer.update(app_data);
        }

        // Render
        {
            gl.clear(.{ .color = true, .depth = true });

            world.grid_renderer.render();
            world.blocks_renderer.render();
        }

        glfw.glfwSwapBuffers(window);

        if (app_data.mouse.left_down) |*left| {
            left.is_event = false;
        }

        if (app_data.mouse.right_down) |*right| {
            right.is_event = false;
        }

        app_data.mouse.scroll = null;
    }
}

fn onFramebufferSize(window: ?*glfw.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    const app_data: *AppData = @alignCast(@ptrCast(glfw.glfwGetWindowUserPointer(window.?)));

    app_data.screen.width = @intCast(width);
    app_data.screen.height = @intCast(height);
    app_data.screen.aspect_ratio = if (height == 0) 0.0 else @as(gl.Float, @floatFromInt(width)) / @as(gl.Float, @floatFromInt(height));

    gl.viewport(0, 0, app_data.screen.width, app_data.screen.height);
}

fn onMouseButton(window: ?*glfw.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.C) void {
    _ = mods;

    const app_data: *AppData = @alignCast(@ptrCast(glfw.glfwGetWindowUserPointer(window.?)));

    switch (button) {
        // TODO: Ensure this is exhaustive
        glfw.GLFW_MOUSE_BUTTON_LEFT => app_data.mouse.left_down = switch (action) {
            glfw.GLFW_PRESS => .{
                .down = app_data.mouse.position,
                .is_event = true,
            },
            glfw.GLFW_RELEASE => null,
            else => unreachable,
        },
        glfw.GLFW_MOUSE_BUTTON_RIGHT => app_data.mouse.right_down = switch (action) {
            glfw.GLFW_PRESS => .{
                .down = app_data.mouse.position,
                .is_event = true,
            },
            glfw.GLFW_RELEASE => null,
            else => unreachable,
        },
        else => {},
    }
}

fn onScroll(window: ?*glfw.GLFWwindow, xoffset: f64, yoffset: f64) callconv(.C) void {
    _ = xoffset;

    const app_data: *AppData = @alignCast(@ptrCast(glfw.glfwGetWindowUserPointer(window.?)));

    // TODO: Ensure no DPI scaling has to be done (it doesn't really matter for this app, tho)
    app_data.mouse.scroll = .{ .y_offset = yoffset };
}
