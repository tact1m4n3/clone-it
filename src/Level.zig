const std = @import("std");
const Allocator = std.mem.Allocator;
const zlm = @import("zlm");

const uzlm = zlm.SpecializeOn(u32);

const CubeRenderer = @import("CubeRenderer.zig");

const max_level_width = 16;
const max_level_height = 16;
const max_level_data_size = 0x1000;

const Level = @This();

allocator: Allocator,
offset: zlm.Vec2,
clones: []Clone,
layout: [max_level_height][max_level_width]?Block,

pub fn init(allocator: Allocator, id: u8) !Level {
    var buf: [3]u8 = undefined;
    const n = std.fmt.formatIntBuf(&buf, id, 10, .lower, .{});
    var level_dir = try std.fs.cwd().makeOpenPath("assets/levels/", .{});
    defer level_dir.close();

    const data = try level_dir.readFileAlloc(allocator, buf[0..n], max_level_data_size);
    defer allocator.free(data);

    var parts = std.mem.split(u8, std.mem.trimRight(u8, data, "\n"), "\n\n");
    const clone_part = parts.next().?;
    const layout_part = parts.next().?;

    var clone_iter = std.mem.split(u8, clone_part, "\n");
    const clone_count = std.fmt.parseInt(u8, clone_iter.next().?, 10) catch unreachable;

    const clones = try allocator.alloc(Clone, clone_count);
    for (clones) |*clone| {
        const clone_data = clone_iter.next().?;
        var props = std.mem.split(u8, clone_data, ",");

        const start_pos_x = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
        const start_pos_y = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
        const target_pos_x = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
        const target_pos_y = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;

        const start_position = uzlm.vec2(start_pos_x, start_pos_y);

        clone.* = .{
            .start_position = start_position,
            .current_position = start_position,
            .target_position = uzlm.vec2(target_pos_x, target_pos_y),
        };
    }

    var layout: [max_level_height][max_level_width]?Block = [_][max_level_width]?Block{[_]?Block{null} ** max_level_width} ** max_level_height;

    var min_position = uzlm.vec2(max_level_width, max_level_height);
    var max_position = uzlm.vec2(0, 0);

    var block_iter = std.mem.split(u8, layout_part, "\n");
    while (block_iter.next()) |block_data| {
        var props = std.mem.split(u8, block_data, ",");

        const pos_x = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
        if (pos_x < min_position.x) min_position.x = pos_x;
        if (pos_x > max_position.x) max_position.x = pos_x;

        const pos_y = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
        if (pos_y < min_position.y) min_position.y = pos_y;
        if (pos_y > max_position.y) max_position.y = pos_y;

        const typ: BlockKind = @enumFromInt(std.fmt.parseInt(u32, props.next().?, 10) catch unreachable);
        switch (typ) {
            .ground => layout[pos_y][pos_x] = .ground,
            .button => {
                const x = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
                const y = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
                layout[pos_y][pos_x] = .{ .button = .{
                    .act = uzlm.vec2(x, y),
                    .pressed = false,
                } };
            },
            .portal => {
                const x = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
                const y = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
                layout[pos_y][pos_x] = .{ .portal = .{
                    .to = uzlm.vec2(x, y),
                    .active = false,
                } };
            },
        }
    }

    const level_size = max_position.sub(min_position);
    const offset = uvec2_to_vec2(min_position).add(uvec2_to_vec2(level_size).scale(1.0 / 2.0));

    return .{
        .allocator = allocator,
        .offset = offset,
        .clones = clones,
        .layout = layout,
    };
}

pub fn deinit(self: Level) void {
    self.allocator.free(self.clones);
}

pub inline fn tile_to_world(self: Level, tile: uzlm.Vec2) zlm.Vec3 {
    return zlm.vec3(@as(f32, @floatFromInt(tile.x)) - self.offset.x, 0, self.offset.y - @as(f32, @floatFromInt(tile.y)));
}

pub fn render(self: Level, cube_renderer: *CubeRenderer, model_matrix: zlm.Mat4, view_proj_matrix: zlm.Mat4) void {
    var i: u32 = 0;
    while (i < max_level_height) : (i += 1) {
        var j: u32 = 0;
        while (j < max_level_width) : (j += 1) {
            const world_position = self.tile_to_world(uzlm.vec2(j, i));
            const tile_matrix = zlm.Mat4.createTranslationXYZ(
                world_position.x,
                world_position.y - 0.5,
                world_position.z,
            );

            if (self.layout[i][j]) |block| {
                for (self.clones) |*clone| {
                    if (clone.target_position.x == j and clone.target_position.y == i) {
                        cube_renderer.render(tile_matrix.mul(model_matrix), view_proj_matrix, zlm.vec4(1, 0.435, 0.349, 1));
                        break;
                    }
                } else {
                    switch (block) {
                        .ground => {
                            cube_renderer.render(tile_matrix.mul(model_matrix), view_proj_matrix, zlm.vec4(0.925, 0.808, 0.557, 1));
                        },
                        .button => {
                            cube_renderer.render(tile_matrix.mul(model_matrix), view_proj_matrix, zlm.vec4(0.749, 0.604, 0.792, 1));
                        },
                        .portal => {
                            cube_renderer.render(tile_matrix.mul(model_matrix), view_proj_matrix, zlm.vec4(0.22, 0.38, 0.549, 1));
                        },
                    }
                }
            }
        }
    }
}

pub const Clone = struct {
    start_position: uzlm.Vec2,
    current_position: uzlm.Vec2,
    target_position: uzlm.Vec2,
};

pub const BlockKind = enum(u8) {
    ground = 0,
    button = 1,
    portal = 2,
};

pub const Block = union(BlockKind) {
    ground,
    button: struct {
        act: uzlm.Vec2,
        pressed: bool,
    },
    portal: struct {
        to: uzlm.Vec2,
        active: bool,
    },
};

fn uvec2_to_vec2(v: uzlm.Vec2) zlm.Vec2 {
    return zlm.vec2(@floatFromInt(v.x), @floatFromInt(v.y));
}
