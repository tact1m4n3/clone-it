const std = @import("std");
const Allocator = std.mem.Allocator;
const gl = @import("zgl");
const zlm = @import("zlm");

const CubeRenderer = @import("CubeRenderer.zig");
const Transform = @import("Transform.zig");

const ParticleSystem = @This();

const Particle = struct {
    active: bool,

    transform: Transform = .{},
    velocity: zlm.Vec3 = zlm.Vec3.zero,
    velocity_variation: zlm.Vec3 = zlm.Vec3.zero,
    angular_momentum: zlm.Vec3 = zlm.Vec3.zero,
    scale_variation: zlm.Vec3 = zlm.Vec3.zero,

    color: zlm.Vec4 = zlm.Vec4.zero,
    color_variation: zlm.Vec4 = zlm.Vec4.zero,

    life_remaining: f32 = 0,
};

pub const EmitSettings = struct {
    position: zlm.Vec3,
    velocity: zlm.Vec3,
    velocity_variation: zlm.Vec3,

    rotation: zlm.Vec3,
    angular_momentum: zlm.Vec3,

    initial_scale: zlm.Vec3,
    final_scale: zlm.Vec3,

    initial_color: zlm.Vec4,
    final_color: zlm.Vec4,

    lifetime: f32,
};

allocator: Allocator,
particles: []Particle,
next_index: usize,

pub fn init(allocator: Allocator, pool_size: usize) !ParticleSystem {
    const particles = try allocator.alloc(Particle, pool_size);
    @memset(particles, .{ .active = false });
    return .{
        .allocator = allocator,
        .particles = particles,
        .next_index = 0,
    };
}

pub fn deinit(self: ParticleSystem) void {
    self.allocator.free(self.particles);
}

pub fn emit(self: *ParticleSystem, settings: EmitSettings) void {
    self.particles[self.next_index] = .{
        .active = true,

        .transform = .{
            .position = settings.position,
            .rotation = settings.rotation,
            .scale = settings.initial_scale,
        },
        .velocity = settings.velocity,
        .velocity_variation = settings.velocity_variation,
        .angular_momentum = settings.angular_momentum,
        .scale_variation = settings.final_scale.sub(settings.initial_scale).scale(1 / settings.lifetime),

        .color = settings.initial_color,
        .color_variation = settings.final_color.sub(settings.initial_color).scale(1 / settings.lifetime),

        .life_remaining = settings.lifetime,
    };

    self.next_index += 1;

    if (self.next_index == self.particles.len) {
        self.next_index = 0;
    }
}

pub fn update(self: *ParticleSystem, dt: f32) void {
    for (self.particles) |*particle| {
        if (!particle.active) continue;
        particle.velocity = particle.velocity.add(particle.velocity_variation.scale(dt));
        particle.transform.position = particle.transform.position.add(particle.velocity.scale(dt));
        particle.transform.rotation = particle.transform.rotation.add(particle.angular_momentum.scale(dt));
        particle.transform.scale = particle.transform.scale.add(particle.scale_variation.scale(dt));
        particle.color = particle.color.add(particle.color_variation.scale(dt));
        particle.life_remaining -= dt;
        if (particle.life_remaining <= 0)
            particle.active = false;
    }
}

pub fn render(self: ParticleSystem, renderer: *CubeRenderer, view_proj_matrix: zlm.Mat4) void {
    // TODO: maybe before rendering we should sort the particles in terms of their position for transparency to work

    for (self.particles) |*particle| {
        if (!particle.active) continue;
        renderer.render(particle.transform.compute_matrix(), view_proj_matrix, particle.color);
    }
}

///
/// Utility struct for keeping track of how many particles to spawn
///
pub const Timer = struct {
    interval: f32,
    time: f32 = 0,

    pub fn update(self: *Timer, dt: f32) u32 {
        self.time += dt;
        return if (self.time >= self.interval) blk: {
            const real = self.time / self.interval;
            const count = @floor(real);
            self.time = self.time - count * self.interval;
            break :blk @intFromFloat(count);
        } else 0;
    }
};
