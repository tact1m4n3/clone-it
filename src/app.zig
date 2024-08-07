const std = @import("std");
const Allocator = std.mem.Allocator;
const Random = std.Random;
const Timer = std.time.Timer;
const gl = @import("zgl");
const zlm = @import("zlm");
const zaudio = @import("zaudio");

const zlm_f64 = zlm.SpecializeOn(f64);

const c = @import("c.zig");
const Assets = @import("Assets.zig");
const Scene = @import("Scene.zig");
const SceneRunner = @import("SceneRunner.zig");
const MenuScene = @import("scenes/Menu.zig");
const LevelPickerScene = @import("scenes/LevelPicker.zig");
const LevelPlayerScene = @import("scenes/LevelPlayer.zig");

pub const State = struct {
    window: ?*c.struct_GLFWwindow,
    audio_engine: *zaudio.Engine,
    assets: *Assets,
    menu_scene: MenuScene = undefined,
    level_picker_scene: LevelPickerScene = undefined,
    level_player_scene: LevelPlayerScene = undefined,
    scene_runner: SceneRunner = undefined,
};

const window_title = "To be changed";
const window_width = 1280;
const window_height = 720;

pub var state: State = undefined;

pub fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const random = prng.random();

    if (c.glfwInit() == c.GLFW_FALSE) {
        return error.GlfwInitError;
    }
    defer _ = c.glfwTerminate();

    _ = c.glfwSetErrorCallback(logGlfwError);

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 1);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    const window = c.glfwCreateWindow(window_width, window_height, window_title, null, null) orelse {
        return error.WindowCreateError;
    };
    defer _ = c.glfwDestroyWindow(window);

    c.glfwSetInputMode(window, c.GLFW_STICKY_KEYS, c.GLFW_TRUE); // so that we don't miss any event
    _ = c.glfwSetFramebufferSizeCallback(window, framebufferSizeCallback);
    _ = c.glfwSetCursorPosCallback(window, cursorPosCallback);
    _ = c.glfwSetKeyCallback(window, keyCallback);
    _ = c.glfwSetMouseButtonCallback(window, mouseButtonCallback);
    _ = c.glfwSetScrollCallback(window, mouseScrollCallback);

    c.glfwMakeContextCurrent(window);
    defer c.glfwMakeContextCurrent(null);

    // idk if we should leave these here
    {
        try gl.loadExtensions(0, struct {
            pub fn getProc(comptime _: comptime_int, name: [:0]const u8) ?*align(4) const anyopaque {
                if (c.glfwGetProcAddress(name)) |func| {
                    return func;
                } else {
                    return @ptrCast(&struct {
                        pub fn procNotFound() callconv(.C) noreturn {
                            @panic("OpenGL function not supported");
                        }
                    }.procNotFound);
                }
            }
        }.getProc);
    }

    zaudio.init(allocator);
    defer zaudio.deinit();

    const audio_engine = try zaudio.Engine.create(null);
    defer audio_engine.destroy();

    var assets = try Assets.init(allocator, audio_engine);
    defer assets.deinit();

    state = .{
        .window = window,
        .audio_engine = audio_engine,
        .assets = &assets,
    };

    assets.background_sound.play();

    state.menu_scene = try MenuScene.init(allocator, random);
    defer state.menu_scene.deinit();

    state.level_picker_scene = try LevelPickerScene.init(allocator, random);
    defer state.level_picker_scene.deinit();

    state.level_player_scene = try LevelPlayerScene.init(allocator, random);
    defer state.level_player_scene.deinit();

    state.scene_runner = try SceneRunner.init(allocator, Scene.from(LevelPlayerScene, &state.level_player_scene));
    // state.scene_runner = try SceneRunner.init(allocator, Scene.from(MenuScene, &state.menu_scene));
    defer state.scene_runner.deinit();

    var timer = Timer.start() catch unreachable;
    while (c.glfwWindowShouldClose(state.window) != c.GLFW_TRUE) {
        c.glfwPollEvents();

        const dt = @as(f32, @floatFromInt(timer.lap())) / @as(f32, @floatFromInt(std.time.ns_per_s));

        // update
        state.scene_runner.update(dt);

        // render
        state.scene_runner.render();

        c.glfwSwapBuffers(state.window);
    }
}

pub fn quit() void {
    c.glfwSetWindowShouldClose(state.window, c.GLFW_TRUE);
}

pub fn getWindowSize() [2]u32 {
    var width: c_int = undefined;
    var height: c_int = undefined;
    c.glfwGetWindowSize(state.window, &width, &height);
    return .{ @intCast(width), @intCast(height) };
}

pub fn getFramebufferSize() [2]u32 {
    var width: c_int = undefined;
    var height: c_int = undefined;
    c.glfwGetFramebufferSize(state.window, &width, &height);
    return .{ @intCast(width), @intCast(height) };
}

pub fn getMousePosition() zlm_f64.Vec2 {
    var xpos: f64 = undefined;
    var ypos: f64 = undefined;
    c.glfwGetCursorPos(state.window, &xpos, &ypos);
    const window_size = getWindowSize();
    return zlm_f64.vec2(xpos, ypos)
        .div(zlm_f64.vec2(@floatFromInt(window_size[0]), @floatFromInt(window_size[1])))
        .sub(zlm_f64.vec2(0.5, 0.5))
        .mul(zlm_f64.vec2(2, -2));
}

pub fn getMouseButtonPressed(button: MouseButton) bool {
    return c.glfwGetMouseButton(state.window, @intFromEnum(button));
}

fn logGlfwError(code: c_int, description: [*c]const u8) callconv(.C) void {
    const log = std.log.scoped(.window);
    log.err("{d}: {s}", .{ code, description });
}

fn framebufferSizeCallback(_: ?*c.struct_GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    state.scene_runner.on_event(.{ .resize = .{ @intCast(width), @intCast(height) } });
}

fn cursorPosCallback(_: ?*c.struct_GLFWwindow, xpos: f64, ypos: f64) callconv(.C) void {
    const window_size = getWindowSize();
    const cursor_pos = zlm_f64.vec2(xpos, ypos)
        .div(zlm_f64.vec2(@floatFromInt(window_size[0]), @floatFromInt(window_size[1])))
        .sub(zlm_f64.vec2(0.5, 0.5))
        .mul(zlm_f64.vec2(2, -2));
    state.scene_runner.on_event(.{ .cursor_pos = cursor_pos });
}

fn keyCallback(_: ?*c.struct_GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    state.scene_runner.on_event(.{ .key = .{
        .key = @enumFromInt(key),
        .scancode = scancode,
        .action = @enumFromInt(action),
        .mods = mods,
    } });
}

fn mouseButtonCallback(_: ?*c.struct_GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.C) void {
    state.scene_runner.on_event(.{ .mouse_button = .{
        .button = @enumFromInt(button),
        .action = @enumFromInt(action),
        .mods = mods,
    } });
}

fn mouseScrollCallback(_: ?*c.struct_GLFWwindow, xoffset: f64, yoffset: f64) callconv(.C) void {
    state.scene_runner.on_event(.{ .mouse_scroll = zlm_f64.vec2(xoffset, yoffset) });
}

// we should use some enums here
pub const Event = union(enum) {
    resize: [2]u32,
    cursor_pos: zlm_f64.Vec2, // x = [-1; 1], y = [-1; 1] (bottom-up)
    key: struct {
        key: Key,
        scancode: c_int,
        action: Action,
        mods: c_int,
    },
    mouse_button: struct {
        button: MouseButton,
        action: Action,
        mods: c_int,
    },
    mouse_scroll: zlm_f64.Vec2,
};

pub const Key = enum(i32) {
    space = 32,
    apostrophe = 39,
    comma = 44,
    minus = 45,
    period = 46,
    slash = 47,
    @"0" = 48,
    @"1" = 49,
    @"2" = 50,
    @"3" = 51,
    @"4" = 52,
    @"5" = 53,
    @"6" = 54,
    @"7" = 55,
    @"8" = 56,
    @"9" = 57,
    semicolon = 59,
    equal = 61,
    a = 65,
    b = 66,
    c = 67,
    d = 68,
    e = 69,
    f = 70,
    g = 71,
    h = 72,
    i = 73,
    j = 74,
    k = 75,
    l = 76,
    m = 77,
    n = 78,
    o = 79,
    p = 80,
    q = 81,
    r = 82,
    s = 83,
    t = 84,
    u = 85,
    v = 86,
    w = 87,
    x = 88,
    y = 89,
    z = 90,
    left_bracket = 91,
    backslash = 92,
    right_bracket = 93,
    grave_accent = 96,
    world_1 = 161,
    world_2 = 162,
    escape = 256,
    enter = 257,
    tab = 258,
    backspace = 259,
    insert = 260,
    delete = 261,
    right = 262,
    left = 263,
    down = 264,
    up = 265,
    page_up = 266,
    page_down = 267,
    home = 268,
    end = 269,
    caps_lock = 280,
    scroll_lock = 281,
    num_lock = 282,
    print_screen = 283,
    pause = 284,
    f1 = 290,
    f2 = 291,
    f3 = 292,
    f4 = 293,
    f5 = 294,
    f6 = 295,
    f7 = 296,
    f8 = 297,
    f9 = 298,
    f10 = 299,
    f11 = 300,
    f12 = 301,
    f13 = 302,
    f14 = 303,
    f15 = 304,
    f16 = 305,
    f17 = 306,
    f18 = 307,
    f19 = 308,
    f20 = 309,
    f21 = 310,
    f22 = 311,
    f23 = 312,
    f24 = 313,
    f25 = 314,
    kp_0 = 320,
    kp_1 = 321,
    kp_2 = 322,
    kp_3 = 323,
    kp_4 = 324,
    kp_5 = 325,
    kp_6 = 326,
    kp_7 = 327,
    kp_8 = 328,
    kp_9 = 329,
    kp_decimal = 330,
    kp_divide = 331,
    kp_multiply = 332,
    kp_subtract = 333,
    kp_add = 334,
    kp_enter = 335,
    kp_equal = 336,
    left_shift = 340,
    left_control = 341,
    left_alt = 342,
    left_super = 343,
    right_shift = 344,
    right_control = 345,
    right_alt = 346,
    right_super = 347,
    menu = 348,
};

pub const MouseButton = enum(i32) {
    left = 0,
    right = 1,
    middle = 2,
    @"4" = 3,
    @"5" = 4,
    @"6" = 5,
    @"7" = 6,
    @"8" = 7,
};

pub const Action = enum(i32) {
    unknown = -1,
    release = 0,
    press = 1,
    repeat = 2,
};
