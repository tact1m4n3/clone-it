const std = @import("std");
const Allocator = std.mem.Allocator;
const Random = std.Random;
const zlm = @import("zlm");

const uzlm = zlm.SpecializeOn(u32);
const izlm = zlm.SpecializeOn(i32);

const Event = @import("app.zig").Event;
const Bbox = @import("raycasting.zig").Bbox;
const CubeRenderer = @import("CubeRenderer.zig");
const ParticleSystem = @import("ParticleSystem.zig");
const ParticleTimer = ParticleSystem.Timer;
const Player = @import("Player.zig");

const max_level_width = 16;
const max_level_height = 16;
const max_level_data_size = 0x1000;

const accent_multiplier = zlm.vec4(0.9, 0.9, 0.9, 1);
const accent_multiplier_2 = zlm.vec4(0.8, 0.8, 0.8, 1);

const clone_block_colors = [_]zlm.Vec4{
    zlm.vec4(0.8, 0.3, 0.2, 1),
    zlm.vec4(0.4, 0.550, 0.41, 1),
};

const clone_colors = blk: {
    var colors: [clone_block_colors.len]zlm.Vec4 = undefined;
    for (clone_block_colors, &colors) |block_color, *clone_color| {
        clone_color.* = block_color.mul(accent_multiplier);
    }
    break :blk colors;
};

const ground_color = zlm.vec4(0.925, 0.808, 0.557, 1);
const button_color = zlm.vec4(0.749, 0.604, 0.792, 1);
const button_particle_color = button_color.mul(accent_multiplier_2);
const button_particle_spawn_time = 0.02;
const portal_color = zlm.vec4(0.22, 0.38, 0.549, 1);
const portal_particle_color = portal_color.mul(accent_multiplier_2);
const portal_particle_spawn_time = 0.02;

const Level = @This();

allocator: Allocator,
random: Random,
id: u8,
offset: zlm.Vec2,
bbox: Bbox,
clones: []Clone,
tiles: [max_level_height][max_level_width]?Block,
particle_system: ?ParticleSystem,
finished: bool = false,

pub fn init(allocator: Allocator, random: Random, id: u8, with_particles: bool) !Level {
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
    std.debug.assert(clone_count <= clone_colors.len);

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

    var tiles: [max_level_height][max_level_width]?Block = [_][max_level_width]?Block{[_]?Block{null} ** max_level_width} ** max_level_height;

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
            .ground => tiles[pos_y][pos_x] = .ground,
            .button => {
                const pull_down = std.fmt.parseInt(u1, props.next().?, 10) catch unreachable == 1;
                tiles[pos_y][pos_x] = .{
                    .button = .{
                        .pressed = false,
                        .pull_down = pull_down,
                        .particle_timer = .{ .interval = button_particle_spawn_time }, // this is fine
                    },
                };
            },
            .portal => {
                const to_x = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
                const to_y = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
                const active_x = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
                const active_y = std.fmt.parseInt(u32, props.next().?, 10) catch unreachable;
                tiles[pos_y][pos_x] = .{ .portal = .{
                    .to = uzlm.vec2(to_x, to_y),
                    .active = uzlm.vec2(active_x, active_y),
                    .particle_timer = .{ .interval = portal_particle_spawn_time },
                } };
            },
        }
    }

    const level_size = max_position.sub(min_position);
    const offset = u2f(min_position).add(u2f(level_size).scale(1.0 / 2.0));

    for (clones, 0..) |*clone, i| {
        clone.player = Player.init(
            zlm.vec3(
                @as(f32, @floatFromInt(clone.start_position.x)) - offset.x,
                0,
                offset.y - @as(f32, @floatFromInt(clone.start_position.y)),
            ),
            clone_colors[i],
        );
    }

    const particle_system = if (with_particles) blk: {
        const particle_system = try ParticleSystem.init(allocator, 100);
        errdefer particle_system.deinit();
        break :blk particle_system;
    } else null;

    return .{
        .allocator = allocator,
        .random = random,
        .id = id,
        .offset = offset,
        .bbox = .{
            .min = zlm.vec3(
                -offset.x,
                -1,
                offset.y,
            ),
            .max = zlm.vec3(
                offset.x,
                0,
                -offset.y,
            ),
        },
        .clones = clones,
        .tiles = tiles,
        .particle_system = particle_system,
    };
}

pub fn deinit(self: Level) void {
    self.allocator.free(self.clones);
    if (self.particle_system) |particle_system| {
        particle_system.deinit();
    }
}

pub inline fn tile_to_world(self: Level, tile: uzlm.Vec2) zlm.Vec3 {
    return zlm.vec3(@as(f32, @floatFromInt(tile.x)) - self.offset.x, 0, self.offset.y - @as(f32, @floatFromInt(tile.y)));
}

pub fn submit_action(self: *Level, action: Action) void {
    for (self.clones) |clone| if (clone.player.state != .idle) return;

    for (self.clones) |*clone| {
        const current_tile = &self.tiles[clone.current_position.y][clone.current_position.x].?;

        switch (action) {
            .move => |dir| {
                if (switch (dir) {
                    .right => if (clone.current_position.x < max_level_width - 1) clone.current_position.add(uzlm.vec2(1, 0)) else null,
                    .left => if (clone.current_position.x > 0) clone.current_position.sub(uzlm.vec2(1, 0)) else null,
                    .forward => if (clone.current_position.y < max_level_height - 1) clone.current_position.add(uzlm.vec2(0, 1)) else null,
                    .backward => if (clone.current_position.y > 0) clone.current_position.sub(uzlm.vec2(0, 1)) else null,
                }) |next_position| {
                    if (self.tiles[next_position.y][next_position.x]) |*next_tile| {
                        clone.current_position = next_position;
                        clone.player.move(self.tile_to_world(next_position));
                        switch (current_tile.*) {
                            .button => |*state| if (!state.pull_down) {
                                state.pressed = false;
                            },
                            else => {},
                        }
                        switch (next_tile.*) {
                            .button => |*state| {
                                state.pressed = true;
                            },
                            else => {},
                        }
                    }
                }
            },
            .teleport => {
                switch (current_tile.*) {
                    .portal => |state| if (self.tiles[state.active.y][state.active.x].?.button.pressed) {
                        clone.current_position = state.to;
                        clone.player.teleport(self.tile_to_world(state.to), false);
                    },
                    else => {},
                }
            },
        }
    }
}

pub fn update(self: *Level, dt: f32) void {
    var level_finished = true;
    var despawn_finished = true;

    for (self.clones) |*clone| {
        if (!clone.current_position.eql(clone.target_position)) {
            level_finished = false;
        }
    }

    for (self.clones) |*clone| {
        if (level_finished and clone.player.state == .idle) {
            clone.player.teleport(zlm.Vec3.zero, true);
        }
        clone.player.update(dt);
        if (clone.player.state != .byebye) {
            despawn_finished = false;
        }
    }

    if (self.particle_system) |*particle_system| {
        var i: u32 = 0;
        while (i < max_level_height) : (i += 1) {
            var j: u32 = 0;
            while (j < max_level_width) : (j += 1) {
                if (self.tiles[i][j]) |*tile| {
                    const world_position = self.tile_to_world(uzlm.vec2(j, i));
                    switch (tile.*) {
                        .button => |*state| {
                            if (state.pressed) {
                                continue;
                            }

                            const particle_count = state.particle_timer.update(dt);
                            for (0..particle_count) |_| {
                                const particle_position = zlm.vec3(
                                    world_position.x + self.random.floatNorm(f32) / 4,
                                    world_position.y - 0.1,
                                    world_position.z + self.random.floatNorm(f32) / 4,
                                );
                                particle_system.emit(.{
                                    .position = particle_position,
                                    .velocity = zlm.Vec3.unitY,
                                    .velocity_variation = zlm.Vec3.unitY.scale(0.5),
                                    .rotation = zlm.Vec3.zero,
                                    .angular_momentum = zlm.Vec3.zero,
                                    .initial_scale = zlm.Vec3.one.scale(0.1),
                                    .final_scale = zlm.Vec3.zero,
                                    .initial_color = button_particle_color,
                                    .final_color = button_particle_color,
                                    .lifetime = 1,
                                });
                            }
                        },
                        .portal => |*state| {
                            if (!self.tiles[state.active.y][state.active.x].?.button.pressed) {
                                continue;
                            }

                            const particle_count = state.particle_timer.update(dt);
                            for (0..particle_count) |_| {
                                const particle_position = zlm.vec3(
                                    world_position.x + self.random.floatNorm(f32) / 4,
                                    world_position.y - 0.1,
                                    world_position.z + self.random.floatNorm(f32) / 4,
                                );
                                particle_system.emit(.{
                                    .position = particle_position,
                                    .velocity = zlm.Vec3.unitY,
                                    .velocity_variation = zlm.Vec3.unitY.scale(0.5),
                                    .rotation = zlm.Vec3.zero,
                                    .angular_momentum = zlm.Vec3.zero,
                                    .initial_scale = zlm.Vec3.one.scale(0.1),
                                    .final_scale = zlm.Vec3.zero,
                                    .initial_color = portal_particle_color,
                                    .final_color = portal_particle_color,
                                    .lifetime = 1,
                                });
                            }
                        },
                        else => {},
                    }
                }
            }
        }

        particle_system.update(dt);
    }

    self.finished = despawn_finished;
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

            if (self.tiles[i][j]) |block| {
                for (self.clones, 0..) |*clone, k| {
                    if (clone.target_position.x == j and clone.target_position.y == i) {
                        cube_renderer.render(tile_matrix.mul(model_matrix), view_proj_matrix, clone_block_colors[k]);
                        break;
                    }
                } else {
                    switch (block) {
                        .ground => cube_renderer.render(tile_matrix.mul(model_matrix), view_proj_matrix, ground_color),
                        .button => cube_renderer.render(tile_matrix.mul(model_matrix), view_proj_matrix, button_color),
                        .portal => cube_renderer.render(tile_matrix.mul(model_matrix), view_proj_matrix, portal_color),
                    }
                }
            }
        }
    }

    for (self.clones) |*clone| {
        clone.player.render(cube_renderer, model_matrix, view_proj_matrix);
    }

    if (self.particle_system) |particle_system| {
        particle_system.render(cube_renderer, view_proj_matrix);
    }
}

pub const Clone = struct {
    start_position: uzlm.Vec2,
    current_position: uzlm.Vec2,
    target_position: uzlm.Vec2,
    player: Player = undefined,
};

pub const BlockKind = enum(u8) {
    ground = 0,
    button = 1,
    portal = 2,
};

pub const Block = union(BlockKind) {
    ground,
    button: struct {
        pressed: bool,
        pull_down: bool,
        particle_timer: ParticleTimer,
    },
    portal: struct {
        to: uzlm.Vec2,
        active: uzlm.Vec2,
        particle_timer: ParticleTimer,
    },
};

pub const Action = union(enum) {
    move: MoveDirection,
    teleport,
};

pub const MoveDirection = enum {
    right,
    left,
    forward,
    backward,
};

fn u2f(v: uzlm.Vec2) zlm.Vec2 {
    return zlm.vec2(@floatFromInt(v.x), @floatFromInt(v.y));
}
