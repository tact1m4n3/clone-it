const std = @import("std");
const log = std.log.scoped(.level_picker);
const Allocator = std.mem.Allocator;
const Random = std.Random;
const gl = @import("zgl");
const zlm = @import("zlm");

const app = @import("../app.zig");
const Event = app.Event;
const animation = @import("../animation.zig");
const raycasting = @import("../raycasting.zig");
const Transform = @import("../Transform.zig");
const Scene = @import("../Scene.zig");
const MenuScene = @import("Menu.zig");
const Level = @import("../Level.zig");
const LevelPlayerScene = @import("LevelPlayer.zig");
const Text = @import("../Text.zig");
const TextRenderer = @import("../TextRenderer.zig");
const CubeRenderer = @import("../CubeRenderer.zig");

const LevelPickerScene = @This();

const PreviewList = std.ArrayList(LevelPreview);

random: Random,
proj_matrix: zlm.Mat4,
view_matrix: zlm.Mat4,
view_proj_matrix: zlm.Mat4,
text_renderer: TextRenderer,
cube_renderer: CubeRenderer,
top_text: Text,
sub_text: Text,
previews: PreviewList,
current_preview: u8 = 0,
prev_preview: ?u8 = null,

pub fn init(allocator: Allocator, random: Random) !LevelPickerScene {
    const frame_buffer_size = app.getFramebufferSize();
    const aspect = @as(f32, @floatFromInt(frame_buffer_size[0])) / @as(f32, @floatFromInt(frame_buffer_size[1]));
    const proj_matrix = zlm.Mat4.createOrthogonal(8 * -aspect, 8 * aspect, -8, 8, -1000, 1000);
    const view_matrix = zlm.Mat4.createLookAt(zlm.vec3(1, 8, 5), zlm.Vec3.zero, zlm.vec3(0, 1, 0));
    const view_proj_matrix = view_matrix.mul(proj_matrix);

    var text_renderer = try TextRenderer.init(allocator);
    errdefer text_renderer.deinit();

    const top_text = Text.init("Choose wisely", .center);
    const sub_text = Text.init("(for your future depends on it)", .center);

    var cube_renderer = try CubeRenderer.init(allocator);
    errdefer cube_renderer.deinit();

    var previews = PreviewList.init(allocator);
    errdefer {
        for (previews.items) |preview| {
            preview.level.deinit();
        }
        previews.deinit();
    }

    var i: u8 = 1;
    while (i < std.math.maxInt(u8)) : (i += 1) {
        const preview = .{ .level = Level.init(allocator, random, i, false) catch break };
        try previews.append(preview);
    }

    if (previews.items.len == 0) {
        return error.NoLevelsFound;
    }

    return .{
        .random = random,
        .proj_matrix = proj_matrix,
        .view_matrix = view_matrix,
        .view_proj_matrix = view_proj_matrix,
        .text_renderer = text_renderer,
        .cube_renderer = cube_renderer,
        .top_text = top_text,
        .sub_text = sub_text,
        .previews = previews,
    };
}

pub fn deinit(self: *LevelPickerScene) void {
    for (self.previews.items) |preview| {
        preview.level.deinit();
    }
    self.previews.deinit();
    self.text_renderer.deinit();
    self.cube_renderer.deinit();
}

pub fn on_load(self_opaque: *anyopaque) void {
    const self: *LevelPickerScene = @ptrCast(@alignCast(self_opaque));

    const frame_buffer_size = app.getFramebufferSize();
    const aspect = @as(f32, @floatFromInt(frame_buffer_size[0])) / @as(f32, @floatFromInt(frame_buffer_size[1]));
    self.proj_matrix = zlm.Mat4.createOrthogonal(8 * -aspect, 8 * aspect, -8, 8, -1000, 1000);
    self.view_proj_matrix = self.view_matrix.mul(self.proj_matrix);
}

pub fn on_event(self_opaque: *anyopaque, event: Event) void {
    const self: *LevelPickerScene = @ptrCast(@alignCast(self_opaque));

    switch (event) {
        .resize => |size| {
            const aspect = @as(f32, @floatFromInt(size[0])) / @as(f32, @floatFromInt(size[1]));
            self.proj_matrix = zlm.Mat4.createOrthogonal(8 * -aspect, 8 * aspect, -8, 8, -1000, 1000);
            self.view_proj_matrix = self.view_matrix.mul(self.proj_matrix);
        },
        .key => |e| {
            if (e.key == .escape and e.action == .press) {
                app.state.scene_runner.change_scene(Scene.from(MenuScene, &app.state.menu_scene));
            }

            if ((e.key == .a or e.key == .left) and e.action == .press) {
                if (self.current_preview > 0) {
                    self.prev_preview = self.current_preview;
                    self.previews.items[self.current_preview].slide_out(.right);

                    self.current_preview -= 1;
                    self.previews.items[self.current_preview].slide_in(.right);
                }
            }

            if ((e.key == .d or e.key == .right) and e.action == .press) {
                if (self.current_preview < self.previews.items.len - 1) {
                    self.prev_preview = self.current_preview;
                    self.previews.items[self.current_preview].slide_out(.left);

                    self.current_preview += 1;
                    self.previews.items[self.current_preview].slide_in(.left);
                }
            }
        },
        else => {},
    }

    if (self.previews.items[self.current_preview].on_event(event, self.view_proj_matrix)) {
        app.state.level_player_scene.load_level(self.previews.items[self.current_preview].level.id) catch log.err("failed to reload level", .{});
        app.state.scene_runner.change_scene(Scene.from(LevelPlayerScene, &app.state.level_player_scene));
    }
}

pub fn update(self_opaque: *anyopaque, dt: f32) void {
    const self: *LevelPickerScene = @ptrCast(@alignCast(self_opaque));

    self.previews.items[self.current_preview].update(dt);
    if (self.prev_preview) |prev_preview| {
        self.previews.items[prev_preview].update(dt);
    }
}

pub fn render(self_opaque: *anyopaque) void {
    const self: *LevelPickerScene = @ptrCast(@alignCast(self_opaque));

    gl.clearColor(0.541, 0.776, 0.816, 1);
    gl.clear(.{ .color = true, .depth = true });

    self.previews.items[self.current_preview].render(&self.cube_renderer, self.view_proj_matrix);
    if (self.prev_preview) |prev_preview| {
        self.previews.items[prev_preview].render(&self.cube_renderer, self.view_proj_matrix);
    }
    self.cube_renderer.flush(self.view_proj_matrix);

    // title
    {
        const model_matrix = zlm.Mat4.createUniformScale(1.5).mul(zlm.Mat4.createTranslationXYZ(0, 6.25, 0));
        self.text_renderer.render(self.top_text, model_matrix, self.view_proj_matrix, zlm.Vec4.one);
    }

    // subtitle
    {
        const model_matrix = zlm.Mat4.createUniformScale(0.8).mul(zlm.Mat4.createTranslationXYZ(0, 5.3, 0));
        self.text_renderer.render(self.sub_text, model_matrix, self.view_proj_matrix, zlm.Vec4.one);
    }

    self.text_renderer.flush(self.proj_matrix);
}

const FloatInterpolation = animation.Interpolate(f32, struct {
    pub fn lerpFn(a: f32, b: f32, t: f32) f32 {
        return a + (b - a) * t;
    }
}.lerpFn);

const Vec3Interpolation = animation.Interpolate(zlm.Vec3, zlm.Vec3.lerp);

pub const LevelPreview = struct {
    const State = union(enum) {
        idle,
        slide_in: struct {
            controller: animation.Controller,
            animation: Vec3Interpolation,
        },
        slide_out: struct {
            controller: animation.Controller,
            animation: Vec3Interpolation,
        },
        hover_in: struct {
            controller: animation.Controller,
            animation: Vec3Interpolation,
        },
        hover_out: struct {
            controller: animation.Controller,
            animation: Vec3Interpolation,
        },
        click: struct {
            controller: animation.Controller,
            animation: Vec3Interpolation,
        },
    };

    pub const SlideDirection = enum {
        left,
        right,
    };

    level: Level,
    transform: Transform = .{},
    hovered: bool = false,
    state: State = .idle,

    pub fn slide_in(self: *LevelPreview, dir: SlideDirection) void {
        self.state = .{ .slide_in = .{
            .controller = animation.Controller.init(0.0, 1.0, animation.functions.easeInOutElastic),
            .animation = .{
                .initial_state = zlm.vec3(20, 0, 0).scale(switch (dir) {
                    .left => 1,
                    .right => -1,
                }),
                .final_state = zlm.vec3(0, 0, 0),
            },
        } };
    }

    pub fn slide_out(self: *LevelPreview, dir: SlideDirection) void {
        self.state = .{ .slide_out = .{
            .controller = animation.Controller.init(0.0, 1.0, animation.functions.easeInOutElastic),
            .animation = .{
                .initial_state = self.transform.position,
                .final_state = zlm.vec3(20, 0, 0).scale(switch (dir) {
                    .left => -1,
                    .right => 1,
                }),
            },
        } };
    }

    ///
    /// Returns true if the preview is pressed.
    ///
    pub fn on_event(self: *LevelPreview, event: Event, view_proj_matrix: zlm.Mat4) bool {
        switch (event) {
            .cursor_pos => |pos| {
                const ray: raycasting.Ray = .{
                    .orig = zlm.vec3(0, 0, -1),
                    .dir = zlm.vec3(@floatCast(pos.x), @floatCast(pos.y / 2), 1), // hacky solution on y
                };

                const bbox = self.level.bbox.transform(self.transform.compute_matrix().mul(view_proj_matrix));

                const intersects = ray.intersects(bbox);
                if (self.state == .idle and intersects) {
                    self.hovered = true;

                    self.state = .{
                        .hover_in = .{
                            .controller = animation.Controller.init(0, 8, animation.functions.linear),
                            .animation = .{
                                .initial_state = self.transform.scale,
                                .final_state = zlm.Vec3.one.scale(1.04),
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
                                .initial_state = self.transform.scale,
                                .final_state = zlm.Vec3.one.scale(0.95),
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

    pub fn update(self: *LevelPreview, dt: f32) void {
        self.transform.position = zlm.Vec3.zero;
        self.transform.scale = zlm.Vec3.one;

        switch (self.state) {
            .idle => {},
            .slide_in => |*state| {
                const t = state.controller.update(dt);
                self.transform.position = state.animation.lerp(t);

                if (state.controller.done())
                    self.state = .idle;
            },
            .slide_out => |*state| {
                const t = state.controller.update(dt);
                self.transform.position = state.animation.lerp(t);
            },
            .hover_in => |*state| {
                const t = state.controller.update(dt);
                self.transform.scale = state.animation.lerp(t);

                if (!self.hovered) {
                    self.state = .{
                        .hover_out = .{
                            .controller = animation.Controller.init(0, 8, animation.functions.linear),
                            .animation = .{
                                .initial_state = self.transform.scale,
                                .final_state = zlm.Vec3.one,
                            },
                        },
                    };
                }
            },
            .hover_out => |*state| {
                const t = state.controller.update(dt);
                self.transform.scale = state.animation.lerp(t);

                if (state.controller.done())
                    self.state = .idle;
            },
            .click => |*state| {
                const t = state.controller.update(dt);
                self.transform.scale = state.animation.lerp(t);

                if (state.controller.done()) {
                    self.state = .{
                        .hover_in = .{
                            .controller = animation.Controller.init(0, 8, animation.functions.linear),
                            .animation = .{
                                .initial_state = self.transform.scale,
                                .final_state = zlm.Vec3.one.scale(1.04),
                            },
                        },
                    };
                }
            },
        }

        self.level.update(dt);
    }

    pub fn render(self: *LevelPreview, cube_renderer: *CubeRenderer, view_proj_matrix: zlm.Mat4) void {
        self.level.render(cube_renderer, self.transform.compute_matrix(), view_proj_matrix);
    }
};
