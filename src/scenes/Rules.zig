const std = @import("std");
const Allocator = std.mem.Allocator;
const Random = std.Random;
const gl = @import("zgl");
const zlm = @import("zlm");

const app = @import("../app.zig");
const Event = app.Event;
const Scene = @import("../Scene.zig");
const Text = @import("../Text.zig");
const TextRenderer = @import("../TextRenderer.zig");
const MenuScene = @import("Menu.zig");

const RulesScene = @This();

const rules_content =
    \\Your goal is to place each player (clone) on it's coresponding tile
    \\with the same color. You can move using arrows, "wasd" or by swiping
    \\on the screen. "t" issues a teleport command, which means all players
    \\on a teleport block (of blue color) shall be teleported to another
    \\analog blue colored block. For a portal to be traversable it has to be
    \\activated (emits particles). Inactive portals are enabled by pressing
    \\a button (moving to a button block of pink color). The portal that a
    \\given button activates is not specified tho it's deducible. A button
    \\that is not pressed emits particles simmilarly to an activated portal.
    \\Some buttons may not stay pressed without a player (clone) standing
    \\on it! Beware, that all actions apply to all players (clones) at once.
    \\In the level picker screen, use arrows or "ad" to move between levels.
    \\Press escape to go to the previous screen. Good luck and have fun! :))
;

random: Random,
proj_matrix: zlm.Mat4,
text_renderer: TextRenderer,
title_text: Text,
rules_text: Text,

pub fn init(allocator: Allocator, random: Random) !RulesScene {
    const frame_buffer_size = app.getFramebufferSize();
    const aspect = @as(f32, @floatFromInt(frame_buffer_size[0])) / @as(f32, @floatFromInt(frame_buffer_size[1]));
    const proj_matrix = zlm.Mat4.createOrthogonal(-aspect, aspect, -1, 1, -1000, 1000);

    const text_renderer = try TextRenderer.init(allocator);
    errdefer text_renderer.deinit();

    const title_text = Text.init("Rules!", .center);
    const rules_text = Text.init(rules_content, .center);

    return .{
        .random = random,
        .proj_matrix = proj_matrix,
        .text_renderer = text_renderer,
        .title_text = title_text,
        .rules_text = rules_text,
    };
}

pub fn deinit(self: *RulesScene) void {
    self.text_renderer.deinit();
}

pub fn on_load(self_opaque: *anyopaque) void {
    const self: *RulesScene = @ptrCast(@alignCast(self_opaque));

    const frame_buffer_size = app.getFramebufferSize();
    const aspect = @as(f32, @floatFromInt(frame_buffer_size[0])) / @as(f32, @floatFromInt(frame_buffer_size[1]));
    self.proj_matrix = zlm.Mat4.createOrthogonal(-aspect, aspect, -1, 1, -1000, 1000);
}

pub fn on_event(self_opaque: *anyopaque, event: Event) void {
    const self: *RulesScene = @ptrCast(@alignCast(self_opaque));

    switch (event) {
        .resize => |size| {
            const aspect = @as(f32, @floatFromInt(size[0])) / @as(f32, @floatFromInt(size[1]));
            self.proj_matrix = zlm.Mat4.createOrthogonal(-aspect, aspect, -1, 1, -1000, 1000);
        },
        .key => |e| {
            if (e.key == .escape and e.action == .press) {
                app.state.scene_runner.change_scene(Scene.from(MenuScene, &app.state.menu_scene));
            }
        },
        else => {},
    }
}

pub fn update(self_opaque: *anyopaque, dt: f32) void {
    _ = dt; // autofix
    const self: *RulesScene = @ptrCast(@alignCast(self_opaque));
    _ = self; // autofix
}

pub fn render(self_opaque: *anyopaque) void {
    const self: *RulesScene = @ptrCast(@alignCast(self_opaque));

    gl.clearColor(0, 0, 0, 1);
    gl.clear(.{ .color = true, .depth = true });

    {
        const model_matrix = zlm.Mat4.createUniformScale(0.12).mul(zlm.Mat4.createTranslationXYZ(0, 0.70, 0));
        self.text_renderer.render(self.title_text, model_matrix, self.proj_matrix, zlm.Vec4.one);
    }

    {
        const model_matrix = zlm.Mat4.createUniformScale(0.085);
        self.text_renderer.render(self.rules_text, model_matrix, self.proj_matrix, zlm.Vec4.one);
    }

    self.text_renderer.flush(self.proj_matrix);
}
