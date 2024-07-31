const std = @import("std");
const zlm = @import("zlm");

const Transform = @import("Transform.zig");

pub fn Interpolate(T: type) type {
    return struct {
        const Self = @This();

        initial_state: T,
        final_state: T,
        lerp_func: *const fn (T, T, f32) T,

        pub fn lerp(self: Self, t: f32) T {
            return self.lerp_func(self.initial_state, self.final_state, t);
        }
    };
}

pub const EasingFunction = *const fn (f32) f32;

pub const Controller = struct {
    speed: f32,
    time: f32,
    func: EasingFunction,

    pub fn init(speed: f32, func: EasingFunction) Controller {
        return .{
            .speed = speed,
            .time = 0,
            .func = func,
        };
    }

    pub fn reset(self: *Controller) void {
        self.time = 0;
    }

    pub fn update(self: *Controller, dt: f32) f32 {
        if (self.time < 1) {
            self.time = std.math.clamp(self.time + self.speed * dt, 0, 1);
        }
        return self.func(self.time);
    }

    pub fn done(self: *Controller) bool {
        return self.time == 1;
    }
};

pub const functions = struct {
    pub fn linear(x: f32) f32 {
        return x;
    }

    pub fn easeOutQuad(x: f32) f32 {
        return 1 - (1 - x) * (1 - x);
    }

    pub fn easeOutCubic(x: f32) f32 {
        return 1 - std.math.pow(f32, 1 - x, 3);
    }

    pub fn reverse(comptime f: EasingFunction) EasingFunction {
        return struct {
            pub fn reverseFn(x: f32) f32 {
                f(1 - x);
            }
        }.reverseFn;
    }

    // could use a different name
    pub fn loopBack(comptime f: EasingFunction) EasingFunction {
        return struct {
            pub fn loopBackFn(x: f32) f32 {
                return if (x < 0.5) f(x * 2) else f(2 - 2 * x);
            }
        }.loopBackFn;
    }
};
