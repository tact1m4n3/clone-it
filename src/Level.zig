const std = @import("std");
const zlm = @import("zlm");

const uzlm = zlm.SpecializeOn(i32);

const CubeRenderer = @import("CubeRenderer.zig");

pub const Clone = struct {
    start_position: uzlm.Vec2,
    target_position: uzlm.Vec2,
};

pub const BlockType = enum(u8) {
    ground = 0,
    button = 1,
    portal = 2,
};

pub const Block = union(BlockType) {
    ground,
    button: uzlm.Vec2,
    portal: uzlm.Vec2,
};

pub const BlockState = union(BlockType) {
    ground,
    button: bool,
    portal: bool,
};

pub const Layout = struct {};

const level_width = 16;
const level_height = 16;
const clone_count = 2;

const Level = @This();

min_position: uzlm.Vec2,
max_position: uzlm.Vec2,
clones: [clone_count]Clone,
layout: [level_height][level_width]?Block,

fn load_level(name: []const u8) Level {
    @setEvalBranchQuota(2000);

    const data = @embedFile("assets/levels/" ++ name);
    var parts = std.mem.split(u8, std.mem.trimRight(u8, data, "\n"), "\n\n");
    const clone_part = parts.next().?;
    const layout_part = parts.next().?;

    var clones: [clone_count]Clone = undefined;

    var clone_iter = std.mem.split(u8, clone_part, "\n");
    for (&clones) |*clone| {
        const clone_data = clone_iter.next().?;
        var props = std.mem.split(u8, clone_data, ",");
        const start_pos_x = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
        const start_pos_y = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
        const target_pos_x = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
        const target_pos_y = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
        clone.* = .{
            .start_position = uzlm.vec2(start_pos_x, start_pos_y),
            .target_position = uzlm.vec2(target_pos_x, target_pos_y),
        };
    }

    var layout: [level_height][level_width]?Block = [_][level_width]?Block{[_]?Block{null} ** level_width} ** level_height;

    var min_position = uzlm.vec2(level_width, level_height);
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

        const typ: BlockType = @enumFromInt(std.fmt.parseInt(u32, props.next().?, 10) catch unreachable);
        switch (typ) {
            .ground => layout[pos_y][pos_x] = .ground,
            .button => {
                const x = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
                const y = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
                layout[pos_y][pos_x] = .{ .button = uzlm.vec2(x, y) };
            },
            .portal => {
                const x = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
                const y = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
                layout[pos_y][pos_x] = .{ .portal = uzlm.vec2(x, y) };
            },
        }
    }

    return .{
        .min_position = min_position,
        .max_position = max_position,
        .clones = clones,
        .layout = layout,
    };
}

pub const level_1 = load_level("1.level");

pub const Runner = struct {};

pub fn render(self: Level, cube_renderer: *CubeRenderer, model_matrix: zlm.Mat4, view_proj_matrix: zlm.Mat4) void {
    const level_size = self.max_position.sub(self.min_position);
    const offset_x = level_size.scale(-1).add(self.min_position);
    const offset_y = level_size.scale(-1).add(self.min_position);

    for (0..level_height) |i| {
        for (0..level_width) |j| {
            const tile_matrix = zlm.Mat4.createTranslationXYZ(
                @as(f32, @floatFromInt(@as(i32, @intCast(j)) - offset.x)),
                -0.5,
                @as(f32, @floatFromInt(offset.x - @as(i32, @intCast(i)))),
            );

            if (self.layout[i][j]) |block| {
                inline for (&self.clones) |*clone| {
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
