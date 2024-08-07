const std = @import("std");
const Allocator = std.mem.Allocator;
const Random = std.Random;
const gl = @import("zgl");
const zlm = @import("zlm");

const app = @import("../app.zig");
const Event = app.Event;
const Scene = @import("../Scene.zig");
const MenuScene = @import("Menu.zig");
const LevelPlayerScene = @import("LevelPlayer.zig");
const Text = @import("../Text.zig");
const ui = @import("../ui.zig");
const TextRenderer = @import("../TextRenderer.zig");

const LevelPickerScene = @This();

random: Random,
proj_matrix: zlm.Mat4,
text_renderer: TextRenderer,
next_button: ui.Button,
back_button: ui.Button,

pub fn init(allocator: Allocator, random: Random) !LevelPickerScene {
    const frame_buffer_size = app.getFramebufferSize();
    const aspect = @as(f32, @floatFromInt(frame_buffer_size[0])) / @as(f32, @floatFromInt(frame_buffer_size[1]));
    const proj_matrix = zlm.Mat4.createOrthogonal(-aspect, aspect, -1, 1, -1000, 1000);

    const text_renderer = try TextRenderer.init(allocator);
    errdefer text_renderer.deinit();

    const next_text = Text.init("Next", .center);
    const next_button = try ui.Button.init(
        next_text,
        .{ .scale = zlm.vec3(0.2, 0.2, 0.2) },
        zlm.Vec4.one,
    );

    const back_text = Text.init("", .center);
    const back_button = try ui.Button.init(
        back_text,
        .{
            .position = zlm.vec3(-aspect + 0.06, 0.90, 0),
            .scale = zlm.vec3(0.15, 0.15, 0.15),
        },
        zlm.Vec4.one,
    );

    return .{
        .random = random,
        .proj_matrix = proj_matrix,
        .text_renderer = text_renderer,
        .back_button = back_button,
        .next_button = next_button,
    };
}

pub fn deinit(self: *LevelPickerScene) void {
    self.text_renderer.deinit();
}

pub fn on_event(self_opaque: *anyopaque, event: Event) void {
    const self: *LevelPickerScene = @ptrCast(@alignCast(self_opaque));

    switch (event) {
        .resize => |size| {
            const aspect = @as(f32, @floatFromInt(size[0])) / @as(f32, @floatFromInt(size[1]));
            self.proj_matrix = zlm.Mat4.createOrthogonal(-aspect, aspect, -1, 1, -1000, 1000);
        },
        else => {},
    }

    if (self.next_button.on_event(event, self.proj_matrix)) {
        app.state.scene_runner.change_scene(Scene.from(LevelPlayerScene, &app.state.level_player_scene));
    }

    if (self.back_button.on_event(event, self.proj_matrix)) {
        app.state.scene_runner.change_scene(Scene.from(MenuScene, &app.state.menu_scene));
    }
}

pub fn update(self_opaque: *anyopaque, dt: f32) void {
    const self: *LevelPickerScene = @ptrCast(@alignCast(self_opaque));

    self.next_button.update(dt);
    self.back_button.update(dt);
}

pub fn render(self_opaque: *anyopaque) void {
    const self: *LevelPickerScene = @ptrCast(@alignCast(self_opaque));

    gl.clearColor(0, 0, 0, 0);
    gl.clear(.{ .color = true, .depth = true });

    self.next_button.render(&self.text_renderer, self.proj_matrix);
    self.back_button.render(&self.text_renderer, self.proj_matrix);
    self.text_renderer.flush(self.proj_matrix);
}
