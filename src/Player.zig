const std = @import("std");
const Allocator = std.mem.Allocator;
const Timer = std.time.Timer;
const zlm = @import("zlm");

const uzlm = zlm.SpecializeOn(u32);

const animation = @import("animation.zig");
const Transform = @import("Transform.zig");
const CubeRenderer = @import("CubeRenderer.zig");

const Player = @This();

const State = union(enum) {
    idle: struct {
        controller: animation.Controller,
        animation: Vec3Interpolation,
    },
    move: struct {
        controller: animation.Controller,
        animation: Vec3Interpolation,
    },
    teleport: union(enum) {
        despawn: struct {
            particle_timer: std.time.Timer,
            position_controller: animation.Controller,
            position_animation: Vec3Interpolation,
            scale_controller: animation.Controller,
            scale_animation: Vec3Interpolation,
        },
        respawn: struct {
            position_controller: animation.Controller,
            position_animation: Vec3Interpolation,
            scale_controller: animation.Controller,
            scale_animation: Vec3Interpolation,
        },
    },
};

const Vec3Interpolation = animation.Interpolate(zlm.Vec3, zlm.Vec3.lerp);
const TransformInterpolation = animation.Interpolate(Transform, Transform.lerp);

state: State,
position: zlm.Vec3,
color: zlm.Vec4,
model_matrix: zlm.Mat4,

pub fn init(position: zlm.Vec3, color: zlm.Vec4) Player {
    return .{
        .state = createIdleState(position),
        .position = position,
        .color = color,
        .model_matrix = zlm.Mat4.identity,
    };
}

pub fn update(self: *Player, dt: f32) void {
    var transform: Transform = .{};

    switch (self.state) {
        .idle => {
            // const t = state.controller.update(dt);
            // if (state.controller.done()) {
            //     state.controller.reset();
            // }
            //
            transform.position = self.position;
        },
        .move => |*state| {
            const t = state.controller.update(dt);

            transform.position = state.animation.lerp(t);

            if (state.controller.done()) {
                self.state = createIdleState(self.position);
            }
        },
        .teleport => |*tp_state| switch (tp_state.*) {
            .despawn => |*despawn_state| {
                const pos_t = despawn_state.position_controller.update(dt);
                const scale_t = despawn_state.scale_controller.update(dt);

                transform.position = despawn_state.position_animation.lerp(pos_t);
                transform.scale = despawn_state.scale_animation.lerp(scale_t);

                // const spawn_count = despawn_state.particle_timer.read();

                if (despawn_state.position_controller.done() and despawn_state.scale_controller.done()) {
                    self.state = .{
                        .teleport = .{
                            .respawn = .{
                                .position_controller = animation.Controller.init(0, 2.0, animation.functions.easeOutCubic),
                                .position_animation = .{
                                    .initial_state = zlm.vec3(self.position.x, 8.0, self.position.z),
                                    .final_state = self.position,
                                },
                                .scale_controller = animation.Controller.init(0, 1.4, animation.functions.easeOutBack),
                                .scale_animation = .{
                                    .initial_state = zlm.Vec3.zero,
                                    .final_state = zlm.Vec3.one,
                                },
                            },
                        },
                    };
                }
            },
            .respawn => |*respawn_state| {
                const pos_t = respawn_state.position_controller.update(dt);
                const scale_t = respawn_state.scale_controller.update(dt);

                transform.position = respawn_state.position_animation.lerp(pos_t);
                transform.scale = respawn_state.scale_animation.lerp(scale_t);

                if (respawn_state.position_controller.done() and respawn_state.scale_controller.done()) {
                    self.state = createIdleState(self.position);
                }
            },
        },
    }

    transform.position.y += 0.4;
    transform.scale = transform.scale.scale(0.8);

    self.model_matrix = transform.compute_matrix();
}

pub fn render(self: *Player, renderer: *CubeRenderer, view_proj_matrix: zlm.Mat4) void {
    renderer.render(
        self.model_matrix,
        view_proj_matrix,
        self.color,
    );
}

pub fn move(self: *Player, position: zlm.Vec3) bool {
    if (self.state != .idle) {
        return false;
    }

    self.state = .{
        .move = .{
            .controller = animation.Controller.init(0, 1.0, animation.functions.easeInOutQuint),
            .animation = .{
                .initial_state = self.position,
                .final_state = position,
            },
        },
    };

    self.position = position;

    return true;
}

pub fn teleport(self: *Player, position: zlm.Vec3) bool {
    if (self.state != .idle) {
        return false;
    }

    self.state = .{
        .teleport = .{
            .despawn = .{
                // .particle_timer = Timer.start() catch unreachable, // this should never fail on a normal computer :))
                .position_controller = animation.Controller.init(0.6, 2.0, animation.functions.easeInCubic),
                .position_animation = .{
                    .initial_state = self.position,
                    .final_state = zlm.vec3(self.position.x, 8.0, self.position.z),
                },
                .scale_controller = animation.Controller.init(0, 1.4, animation.functions.easeInBack),
                .scale_animation = .{
                    .initial_state = zlm.Vec3.one,
                    .final_state = zlm.Vec3.zero,
                },
            },
        },
    };

    self.position = position;

    return true;
}

fn createIdleState(position: zlm.Vec3) State {
    return .{
        .idle = .{
            .controller = animation.Controller.init(0, 0.5, animation.functions.loopBack(animation.functions.easeInOutQuad)),
            .animation = .{
                .initial_state = position,
                .final_state = zlm.vec3(position.x, position.y - 0.05, position.z),
            },
        },
    };
}
