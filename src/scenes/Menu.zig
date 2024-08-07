const std = @import("std");
const Allocator = std.mem.Allocator;
const Random = std.Random;
const gl = @import("zgl");
const zlm = @import("zlm");

const app = @import("../app.zig");
const Event = app.Event;
const Scene = @import("../Scene.zig");
const LevelPickerScene = @import("LevelPicker.zig");
const Text = @import("../Text.zig");
const ui = @import("../ui.zig");
const TextRenderer = @import("../TextRenderer.zig");

const MenuScene = @This();

random: Random,
proj_matrix: zlm.Mat4,
text_renderer: TextRenderer,
play_button: ui.Button,
quit_button: ui.Button,

pub fn init(allocator: Allocator, random: Random) !MenuScene {
    const frame_buffer_size = app.getFramebufferSize();
    const aspect = @as(f32, @floatFromInt(frame_buffer_size[0])) / @as(f32, @floatFromInt(frame_buffer_size[1]));
    const proj_matrix = zlm.Mat4.createOrthogonal(-aspect, aspect, -1, 1, -1000, 1000);

    const text_renderer = try TextRenderer.init(allocator);

    const play_text = Text.init("Play", .center);
    const play_button = try ui.Button.init(
        play_text,
        .{ .position = zlm.vec3(0, 0.12, 0), .scale = zlm.vec3(0.2, 0.2, 0.2) },
        zlm.Vec4.one,
    );

    const quit_text = Text.init("Quit", .center);
    const quit_button = try ui.Button.init(
        quit_text,
        .{ .position = zlm.vec3(0, -0.12, 0), .scale = zlm.vec3(0.2, 0.2, 0.2) },
        zlm.Vec4.one,
    );

    return .{
        .random = random,
        .proj_matrix = proj_matrix,
        .text_renderer = text_renderer,
        .play_button = play_button,
        .quit_button = quit_button,
    };
}

pub fn deinit(self: *MenuScene) void {
    self.text_renderer.deinit();
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

    if (self.quit_button.on_event(event, self.proj_matrix)) {
        app.quit();
    }
}

pub fn update(self_opaque: *anyopaque, dt: f32) void {
    const self: *MenuScene = @ptrCast(@alignCast(self_opaque));

    self.play_button.update(dt);
    self.quit_button.update(dt);
}

pub fn render(self_opaque: *anyopaque) void {
    const self: *MenuScene = @ptrCast(@alignCast(self_opaque));

    gl.clearColor(0, 0, 0, 0);
    gl.clear(.{ .color = true, .depth = true });

    self.play_button.render(&self.text_renderer, self.proj_matrix);
    self.quit_button.render(&self.text_renderer, self.proj_matrix);
    self.text_renderer.flush(self.proj_matrix);
}
