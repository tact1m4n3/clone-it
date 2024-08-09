const std = @import("std");
const log = std.log.scoped(.level_player);
const Allocator = std.mem.Allocator;
const Random = std.Random;
const gl = @import("zgl");
const zlm = @import("zlm");

const app = @import("../app.zig");
const animation = @import("../animation.zig");
const Event = app.Event;
const Scene = @import("../Scene.zig");
const LevelPickerScene = @import("LevelPicker.zig");
const Player = @import("../Player.zig");
const CubeRenderer = @import("../CubeRenderer.zig");
const Text = @import("../Text.zig");
const TextRenderer = @import("../TextRenderer.zig");
const Level = @import("../Level.zig");
const Action = Level.Action;
const MoveDirection = Level.MoveDirection;

const LevelPlayerScene = @This();

const FloatInterpolation = animation.Interpolate(f32, struct {
    pub fn lerpFn(a: f32, b: f32, t: f32) f32 {
        return a + (b - a) * t;
    }
}.lerpFn);

const State = union(enum) {
    play: MovementReader,
    finish: struct {
        transparency: f32 = 0,
        controller: animation.Controller,
        animation: FloatInterpolation,
    },
};

allocator: Allocator,
random: Random,
proj_matrix: zlm.Mat4,
view_matrix: zlm.Mat4,
view_proj_matrix: zlm.Mat4,
cube_renderer: CubeRenderer,
text_renderer: TextRenderer,
finish_text: Text,
level: Level,
level_id: u8 = 1,
state: State = .{ .play = .{} },

pub fn init(allocator: Allocator, random: Random) !LevelPlayerScene {
    const frame_buffer_size = app.getFramebufferSize();
    const aspect = @as(f32, @floatFromInt(frame_buffer_size[0])) / @as(f32, @floatFromInt(frame_buffer_size[1]));
    const proj_matrix = zlm.Mat4.createOrthogonal(8 * -aspect, 8 * aspect, -8, 8, -1000, 1000);
    const view_matrix = zlm.Mat4.createLookAt(zlm.vec3(1, 8, 5), zlm.Vec3.zero, zlm.vec3(0, 1, 0));
    const view_proj_matrix = view_matrix.mul(proj_matrix);

    var cube_renderer = try CubeRenderer.init(allocator);
    errdefer cube_renderer.deinit();

    var text_renderer = try TextRenderer.init(allocator);
    errdefer text_renderer.deinit();

    const level = try Level.init(allocator, random, 1, true);
    errdefer level.deinit();

    return .{
        .allocator = allocator,
        .random = random,
        .proj_matrix = proj_matrix,
        .view_matrix = view_matrix,
        .view_proj_matrix = view_proj_matrix,
        .cube_renderer = cube_renderer,
        .text_renderer = text_renderer,
        .finish_text = Text.init("Level completed. Tap to exit...", .center),
        .level = level,
    };
}

pub fn deinit(self: *LevelPlayerScene) void {
    self.cube_renderer.deinit();
    self.text_renderer.deinit();
    self.level.deinit();
}

pub fn load_level(self: *LevelPlayerScene, id: u8) !void {
    const level = try Level.init(self.allocator, self.random, id, true);
    self.level_id = id;
    self.level.deinit();
    self.level = level;
    self.state = .{ .play = .{} };
}

pub fn on_load(self_opaque: *anyopaque) void {
    const self: *LevelPlayerScene = @ptrCast(@alignCast(self_opaque));

    const frame_buffer_size = app.getFramebufferSize();
    const aspect = @as(f32, @floatFromInt(frame_buffer_size[0])) / @as(f32, @floatFromInt(frame_buffer_size[1]));
    self.proj_matrix = zlm.Mat4.createOrthogonal(8 * -aspect, 8 * aspect, -8, 8, -1000, 1000);
    self.view_proj_matrix = self.view_matrix.mul(self.proj_matrix);
}

pub fn on_event(self_opaque: *anyopaque, event: Event) void {
    const self: *LevelPlayerScene = @ptrCast(@alignCast(self_opaque));

    switch (event) {
        .resize => |size| {
            const aspect = @as(f32, @floatFromInt(size[0])) / @as(f32, @floatFromInt(size[1]));
            self.proj_matrix = zlm.Mat4.createOrthogonal(8 * -aspect, 8 * aspect, -8, 8, -1000, 1000);
            self.view_proj_matrix = self.view_matrix.mul(self.proj_matrix);
        },
        .key => |e| {
            if (e.key == .escape and e.action == .press) {
                app.state.scene_runner.change_scene(Scene.from(LevelPickerScene, &app.state.level_picker_scene));
            }

            if (e.key == .r and e.action == .press and e.mods.control == true) {
                self.load_level(self.level_id) catch log.err("failed to reload level", .{});
            }
        },
        else => {},
    }

    switch (self.state) {
        .play => |*movement_reader| {
            switch (event) {
                .key => |e| {
                    if ((e.key == .w or e.key == .up) and e.action == .press) {
                        self.level.submit_action(.{ .move = .forward });
                    }
                    if ((e.key == .a or e.key == .left) and e.action == .press) {
                        self.level.submit_action(.{ .move = .left });
                    }
                    if ((e.key == .s or e.key == .down) and e.action == .press) {
                        self.level.submit_action(.{ .move = .backward });
                    }
                    if ((e.key == .d or e.key == .right) and e.action == .press) {
                        self.level.submit_action(.{ .move = .right });
                    }
                    if (e.key == .t and e.action == .press) {
                        self.level.submit_action(.teleport);
                    }
                },
                else => {},
            }
            movement_reader.on_event(event);
        },
        .finish => {
            switch (event) {
                .mouse_button => |e| {
                    if (e.button == .left and e.action == .press) {
                        app.state.scene_runner.change_scene(Scene.from(LevelPickerScene, &app.state.level_picker_scene));
                    }
                },
                else => {},
            }
        },
    }
}

pub fn update(self_opaque: *anyopaque, dt: f32) void {
    const self: *LevelPlayerScene = @ptrCast(@alignCast(self_opaque));

    switch (self.state) {
        .play => |*movement_reader| {
            if (movement_reader.update()) |dir| {
                self.level.submit_action(.{ .move = dir });
            }

            if (self.level.finished) self.state = .{
                .finish = .{
                    .controller = animation.Controller.init(0, 1, animation.functions.easeOutQuad),
                    .animation = .{
                        .initial_state = 0,
                        .final_state = 1,
                    },
                },
            };
        },
        .finish => |*state| {
            const t = state.controller.update(dt);
            state.transparency = state.animation.lerp(t);
        },
    }

    self.level.update(dt);
}

pub fn render(self_opaque: *anyopaque) void {
    const self: *LevelPlayerScene = @ptrCast(@alignCast(self_opaque));

    gl.clearColor(0.541, 0.776, 0.816, 1);
    gl.clear(.{ .color = true, .depth = true });

    self.level.render(&self.cube_renderer, zlm.Mat4.identity, self.view_proj_matrix);
    self.cube_renderer.flush(self.view_proj_matrix);

    switch (self.state) {
        .finish => |state| {
            self.text_renderer.render(self.finish_text, zlm.Mat4.createUniformScale(1.5), self.proj_matrix, zlm.vec4(1, 1, 1, state.transparency));
        },
        else => {},
    }
    self.text_renderer.flush(self.proj_matrix);
}

const MovementReader = struct {
    const dir_threshold: f32 = 0.01;
    const mag_threshold: f32 = 0.2;

    press_position: ?zlm.Vec2 = null,
    delta: zlm.Vec2 = zlm.Vec2.zero,
    direction: ?MoveDirection = null,
    should_act: bool = true,
    take_action: bool = false,

    pub fn on_event(self: *MovementReader, event: Event) void {
        const position = app.getMousePosition();

        switch (event) {
            .mouse_button => |e| {
                if (e.button == .left) {
                    if (e.action == .press) {
                        self.press_position = zlm.vec2(@floatCast(position.x), @floatCast(position.y));
                    } else if (e.action == .release) {
                        self.press_position = null;
                        self.take_action = self.should_act;
                    }
                } else if (e.button == .right) {
                    if (e.action == .press) {
                        self.should_act = false;
                    } else {
                        self.should_act = true;
                    }
                }
            },
            else => {},
        }
    }

    pub fn update(self: *MovementReader) ?MoveDirection {
        const position = app.getMousePosition();

        if (self.press_position) |pos| {
            self.delta = zlm.vec2(@floatCast(position.x), @floatCast(position.y)).sub(pos);
            if (self.direction == null and self.delta.length() > dir_threshold) {
                self.direction =
                    if (@abs(self.delta.x) > @abs(self.delta.y))
                    if (self.delta.x > 0) .right else .left
                else if (self.delta.y > 0) .forward else .backward;
            }
        }

        if (self.take_action) {
            self.take_action = false;
            defer self.delta = zlm.Vec2.zero;
            defer self.direction = null;
            if (self.direction) |dir| {
                if (project(dir, self.delta) > mag_threshold) {
                    return dir;
                }
            }
        }

        return null;
    }

    fn project(self: MoveDirection, v: zlm.Vec2) f32 {
        return switch (self) {
            .left => -v.x,
            .right => v.x,
            .forward => v.y,
            .backward => -v.y,
        };
    }
};
