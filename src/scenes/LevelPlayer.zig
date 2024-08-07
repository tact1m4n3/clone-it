const std = @import("std");
const Allocator = std.mem.Allocator;
const Random = std.Random;
const gl = @import("zgl");
const zlm = @import("zlm");

const app = @import("../app.zig");
const Event = app.Event;
const Player = @import("../Player.zig");
const CubeRenderer = @import("../CubeRenderer.zig");
const World = @import("../World.zig");

const LevelPlayerScene = @This();

random: Random,
proj_matrix: zlm.Mat4,
view_matrix: zlm.Mat4,
view_proj_matrix: zlm.Mat4,
cube_renderer: CubeRenderer,
player: Player,
world: World,

pub fn init(allocator: Allocator, random: Random) !LevelPlayerScene {
    const frame_buffer_size = app.getFramebufferSize();
    const aspect = @as(f32, @floatFromInt(frame_buffer_size[0])) / @as(f32, @floatFromInt(frame_buffer_size[1]));
    // const proj_matrix = zlm.Mat4.createPerspective(zlm.toRadians(45.0), aspect, 0.1, 100);
    const proj_matrix = zlm.Mat4.createOrthogonal(6 * -aspect, 6 * aspect, -6, 6, -1000, 1000);
    // const view_matrix = zlm.Mat4.createAngleAxis(zlm.vec3(1, 0.1, 0), 45);
    const view_matrix = zlm.Mat4.createLookAt(zlm.vec3(1, 8, 5), zlm.Vec3.zero, zlm.vec3(0, 1, 0));
    const view_proj_matrix = view_matrix.mul(proj_matrix);

    var cube_renderer = try CubeRenderer.init(allocator);
    errdefer cube_renderer.deinit();

    const player = Player.init(zlm.vec3(-4, 0, -3), zlm.vec4(0.8, 0.8, 0.8, 1));

    const world = try World.init(allocator);
    world.grid_renderer.uploadData();
    world.blocks_renderer.uploadBlockAtlas();
    world.blocks_renderer.uploadData();

    return .{
        .random = random,
        .proj_matrix = proj_matrix,
        .view_matrix = view_matrix,
        .view_proj_matrix = view_proj_matrix,
        .cube_renderer = cube_renderer,
        .player = player,
        .world = world,
    };
}

pub fn deinit(self: *LevelPlayerScene) void {
    self.cube_renderer.deinit();
    self.world.deinit();
}

pub fn on_event(self_opaque: *anyopaque, event: Event) void {
    const self: *LevelPlayerScene = @ptrCast(@alignCast(self_opaque));

    switch (event) {
        .resize => |size| {
            const aspect = @as(f32, @floatFromInt(size[0])) / @as(f32, @floatFromInt(size[1]));
            self.proj_matrix = zlm.Mat4.createOrthogonal(3 * -aspect, 3 * aspect, -3, 3, -1000, 1000);
            self.view_proj_matrix = self.view_matrix.mul(self.proj_matrix);
        },
        .mouse_button => |e| {
            if (e.button == .left and e.action == .press) {
                _ = self.player.move(zlm.vec3(-3, 0, -3));
            }
        },
        else => {},
    }

    self.world.on_event(event);
}

pub fn update(self_opaque: *anyopaque, dt: f32) void {
    const self: *LevelPlayerScene = @ptrCast(@alignCast(self_opaque));

    self.player.update(dt);
    self.world.update();
    self.world.grid_renderer.update();
    self.world.blocks_renderer.update();
}

pub fn render(self_opaque: *anyopaque) void {
    const self: *LevelPlayerScene = @ptrCast(@alignCast(self_opaque));

    gl.clearColor(0.541, 0.776, 0.816, 1);
    gl.clear(.{ .color = true, .depth = true });

    self.world.grid_renderer.render();
    self.world.blocks_renderer.render();

    self.player.render(&self.cube_renderer, self.view_proj_matrix);
    self.cube_renderer.flush(self.view_proj_matrix);
}
