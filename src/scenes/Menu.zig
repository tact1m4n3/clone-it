const std = @import("std");
const Allocator = std.mem.Allocator;
const Random = std.Random;
const gl = @import("zgl");
const zlm = @import("zlm");

const app = @import("../app.zig");
const Event = app.Event;
const Scene = @import("../Scene.zig");
const animation = @import("../animation.zig");
const raycasting = @import("../raycasting.zig");
const Transform = @import("../Transform.zig");
const Text = @import("../Text.zig");
const TextRenderer = @import("../TextRenderer.zig");
const RulesScene = @import("Rules.zig");
const LevelPickerScene = @import("LevelPicker.zig");

const MenuScene = @This();

random: Random,
proj_matrix: zlm.Mat4,
text_renderer: TextRenderer,
title_text: Text,
play_button: Button,
rules_button: Button,
quit_button: Button,

pub fn init(allocator: Allocator, random: Random) !MenuScene {
    const frame_buffer_size = app.getFramebufferSize();
    const aspect = @as(f32, @floatFromInt(frame_buffer_size[0])) / @as(f32, @floatFromInt(frame_buffer_size[1]));
    const proj_matrix = zlm.Mat4.createOrthogonal(-aspect, aspect, -1, 1, -1000, 1000);

    const text_renderer = try TextRenderer.init(allocator);
    errdefer text_renderer.deinit();

    const title_text = Text.init("Clone it!", .center);

    const play_text = Text.init("Play", .center);
    const play_button = try Button.init(
        play_text,
        .{ .position = zlm.Vec3.zero, .scale = zlm.vec3(0.15, 0.15, 0.15) },
        zlm.Vec4.one,
    );

    const rules_text = Text.init("Rules", .center);
    const rules_button = try Button.init(
        rules_text,
        .{ .position = zlm.vec3(0, -0.15, 0), .scale = zlm.vec3(0.15, 0.15, 0.15) },
        zlm.Vec4.one,
    );

    const quit_text = Text.init("Quit", .center);
    const quit_button = try Button.init(
        quit_text,
        .{ .position = zlm.vec3(0, -0.30, 0), .scale = zlm.vec3(0.15, 0.15, 0.15) },
        zlm.Vec4.one,
    );

    return .{
        .random = random,
        .proj_matrix = proj_matrix,
        .text_renderer = text_renderer,
        .title_text = title_text,
        .play_button = play_button,
        .rules_button = rules_button,
        .quit_button = quit_button,
    };
}

pub fn deinit(self: *MenuScene) void {
    self.text_renderer.deinit();
}

pub fn on_load(self_opaque: *anyopaque) void {
    const self: *MenuScene = @ptrCast(@alignCast(self_opaque));

    const frame_buffer_size = app.getFramebufferSize();
    const aspect = @as(f32, @floatFromInt(frame_buffer_size[0])) / @as(f32, @floatFromInt(frame_buffer_size[1]));
    self.proj_matrix = zlm.Mat4.createOrthogonal(-aspect, aspect, -1, 1, -1000, 1000);
}

pub fn on_event(self_opaque: *anyopaque, event: Event) void {
    const self: *MenuScene = @ptrCast(@alignCast(self_opaque));

    switch (event) {
        .resize => |size| {
            const aspect = @as(f32, @floatFromInt(size[0])) / @as(f32, @floatFromInt(size[1]));
            self.proj_matrix = zlm.Mat4.createOrthogonal(-aspect, aspect, -1, 1, -1000, 1000);
        },
        else => {},
    }

    if (self.play_button.on_event(event, self.proj_matrix)) {
        app.state.scene_runner.change_scene(Scene.from(LevelPickerScene, &app.state.level_picker_scene));
    }

    if (self.rules_button.on_event(event, self.proj_matrix)) {
        app.state.scene_runner.change_scene(Scene.from(RulesScene, &app.state.rules_scene));
    }

    if (self.quit_button.on_event(event, self.proj_matrix)) {
        app.quit();
    }
}

pub fn update(self_opaque: *anyopaque, dt: f32) void {
    const self: *MenuScene = @ptrCast(@alignCast(self_opaque));

    self.play_button.update(dt);
    self.rules_button.update(dt);
    self.quit_button.update(dt);
}

pub fn render(self_opaque: *anyopaque) void {
    const self: *MenuScene = @ptrCast(@alignCast(self_opaque));

    gl.clearColor(0, 0, 0, 0);
    gl.clear(.{ .color = true, .depth = true });

    {
        const title_model_matrix = zlm.Mat4.createUniformScale(0.2).mul(zlm.Mat4.createTranslationXYZ(0, 0.55, 0));
        self.text_renderer.render(self.title_text, title_model_matrix, self.proj_matrix, zlm.Vec4.one);
    }

    self.play_button.render(&self.text_renderer, self.proj_matrix);
    self.rules_button.render(&self.text_renderer, self.proj_matrix);
    self.quit_button.render(&self.text_renderer, self.proj_matrix);
    self.text_renderer.flush(self.proj_matrix);
}

const FloatInterpolation = animation.Interpolate(f32, struct {
    pub fn lerpFn(a: f32, b: f32, t: f32) f32 {
        return a + (b - a) * t;
    }
}.lerpFn);

pub const Button = struct {
    const State = union(enum) {
        idle,
        hover_in: struct {
            controller: animation.Controller,
            animation: FloatInterpolation,
        },
        click: struct {
            controller: animation.Controller,
            animation: FloatInterpolation,
        },
        hover_out: struct {
            controller: animation.Controller,
            animation: FloatInterpolation,
        },
    };

    text: Text,
    transform: Transform,
    color: zlm.Vec4,
    scale: f32 = 1,
    hovered: bool = false,
    state: State = .idle,

    pub fn init(text: Text, transform: Transform, color: zlm.Vec4) !Button {
        return .{
            .text = text,
            .transform = transform,
            .color = color,
        };
    }

    ///
    /// Returns true if the button is pressed.
    ///
    pub fn on_event(self: *Button, event: Event, view_proj_matrix: zlm.Mat4) bool {
        switch (event) {
            .cursor_pos => |pos| {
                const ray: raycasting.Ray = .{
                    .orig = zlm.vec3(0, 0, -1),
                    .dir = zlm.vec3(@floatCast(pos.x), @floatCast(pos.y), 1),
                };
                var bbox: raycasting.Bbox = .{
                    .min = zlm.vec3(self.text.rect.position.x, self.text.rect.position.y, 0),
                    .max = zlm.vec3(self.text.rect.position.x + self.text.rect.size.x, self.text.rect.position.y + self.text.rect.size.y, 0),
                };
                bbox = bbox.transform(zlm.Mat4.createUniformScale(self.scale).mul(self.transform.compute_matrix()).mul(view_proj_matrix));

                const intersects = ray.intersects(bbox);
                if (self.state == .idle and intersects) {
                    self.hovered = true;

                    self.state = .{
                        .hover_in = .{
                            .controller = animation.Controller.init(0, 8, animation.functions.linear),
                            .animation = .{
                                .initial_state = self.scale,
                                .final_state = 1.02,
                            },
                        },
                    };
                }

                if (!intersects) {
                    self.hovered = false;
                }
            },
            .mouse_button => |e| {
                if (self.state == .hover_in and e.button == .left and e.action == .press) {
                    app.state.sounds.click.play();

                    self.state = .{
                        .click = .{
                            .controller = animation.Controller.init(0, 4, animation.functions.loopBack(animation.functions.linear)),
                            .animation = .{
                                .initial_state = self.scale,
                                .final_state = 0.95,
                            },
                        },
                    };
                    return true;
                }
            },
            else => {},
        }

        return false;
    }

    pub fn update(self: *Button, dt: f32) void {
        switch (self.state) {
            .idle => {},
            .hover_in => |*state| {
                const t = state.controller.update(dt);
                self.scale = state.animation.lerp(t);

                if (!self.hovered) {
                    self.state = .{
                        .hover_out = .{
                            .controller = animation.Controller.init(0, 8, animation.functions.linear),
                            .animation = .{
                                .initial_state = self.scale,
                                .final_state = 1,
                            },
                        },
                    };
                }
            },
            .click => |*state| {
                const t = state.controller.update(dt);
                self.scale = state.animation.lerp(t);

                if (state.controller.done()) {
                    self.state = .{
                        .hover_in = .{
                            .controller = animation.Controller.init(0, 8, animation.functions.linear),
                            .animation = .{
                                .initial_state = self.scale,
                                .final_state = 1.02,
                            },
                        },
                    };
                }
            },
            .hover_out => |*state| {
                const t = state.controller.update(dt);
                self.scale = state.animation.lerp(t);

                if (state.controller.done())
                    self.state = .idle;
            },
        }
    }

    pub fn render(self: *Button, text_renderer: *TextRenderer, view_proj_matrix: zlm.Mat4) void {
        text_renderer.render(
            self.text,
            zlm.Mat4.createUniformScale(self.scale).mul(self.transform.compute_matrix()),
            view_proj_matrix,
            self.color,
        );
    }
};
