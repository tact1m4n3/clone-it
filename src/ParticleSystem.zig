const std = @import("std");
const Allocator = std.mem.Allocator;
const gl = @import("zgl");
const zlm = @import("zlm");

const Renderer = @import("ParticleRenderer.zig");

const Self = @This();

const Particle = struct {
    active: bool,

    position: zlm.Vec3 = zlm.Vec3.zero,
    velocity: zlm.Vec3 = zlm.Vec3.zero,
    velocity_variation: zlm.Vec3 = zlm.Vec3.zero,

    rotation: zlm.Vec3 = zlm.Vec3.zero,
    angular_momentum: zlm.Vec3 = zlm.Vec3.zero,

    scale: f32 = 0,
    scale_variation: f32 = 0,

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

    initial_scale: f32,
    final_scale: f32,

    initial_color: zlm.Vec4,
    final_color: zlm.Vec4,

    lifetime: f32,
};

allocator: Allocator,
particles: []Particle,
next_index: usize,

pub fn init(allocator: Allocator, pool_size: usize) !Self {
    const particles = try allocator.alloc(Particle, pool_size);
    @memset(particles, .{ .active = false });
    return .{
        .allocator = allocator,
        .particles = particles,
        .next_index = 0,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.particles);
}

pub fn emit(self: *Self, settings: EmitSettings) void {
    self.particles[self.next_index] = .{
        .active = true,

        .position = settings.position,
        .velocity = settings.velocity,
        .velocity_variation = settings.velocity_variation,

        .rotation = settings.rotation,
        .angular_momentum = settings.angular_momentum,

        .scale = settings.initial_scale,
        .scale_variation = (settings.final_scale - settings.initial_scale) / settings.lifetime,

        .color = settings.initial_color,
        .color_variation = settings.final_color.sub(settings.initial_color).scale(1 / settings.lifetime),

        .life_remaining = settings.lifetime,
    };

    self.next_index += 1;

    if (self.next_index == self.particles.len) {
        self.next_index = 0;
    }
}

pub fn update(self: *Self, dt: f32) void {
    for (self.particles) |*particle| {
        if (!particle.active) continue;
        particle.velocity = particle.velocity.add(particle.velocity_variation.scale(dt));
        particle.position = particle.position.add(particle.velocity.scale(dt));
        particle.rotation = particle.rotation.add(particle.angular_momentum.scale(dt));
        particle.scale = particle.scale + particle.scale_variation * dt;
        particle.color = particle.color.add(particle.color_variation.scale(dt));
        particle.life_remaining -= dt;
        if (particle.life_remaining <= 0)
            particle.active = false;
    }
}

pub fn render(self: *Self, renderer: *Renderer) void {
    // TODO: maybe before rendering we should sort the particles in terms of their position for transparency to work

    for (self.particles) |*particle| {
        if (!particle.active) continue;
        const scale = zlm.Mat4.createUniformScale(particle.scale);
        const rotation_x = zlm.Mat4.createAngleAxis(zlm.vec3(1, 0, 0), zlm.toRadians(particle.rotation.x));
        const rotation_y = zlm.Mat4.createAngleAxis(zlm.vec3(0, 1, 0), zlm.toRadians(particle.rotation.y));
        const rotation_z = zlm.Mat4.createAngleAxis(zlm.vec3(0, 0, 1), zlm.toRadians(particle.rotation.z));
        const translation = zlm.Mat4.createTranslationXYZ(particle.position.x, particle.position.y, particle.position.z);

        renderer.render(scale.mul(rotation_x).mul(rotation_y).mul(rotation_z).mul(translation), particle.color);
    }
}
