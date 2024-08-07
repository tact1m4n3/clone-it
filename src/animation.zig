const std = @import("std");
const zlm = @import("zlm");

const Transform = @import("Transform.zig");

pub fn Interpolate(T: type, lerp_func: *const fn (T, T, f32) T) type {
    return struct {
        const Self = @This();

        initial_state: T,
        final_state: T,

        pub fn lerp(self: Self, t: f32) T {
            return lerp_func(self.initial_state, self.final_state, t);
        }
    };
}

pub const EasingFunction = *const fn (f32) f32;

pub const Controller = struct {
    offset: f32,
    speed: f32,
    func: EasingFunction,
    time: f32,

    pub fn init(offset: f32, speed: f32, func: EasingFunction) Controller {
        return .{
            .offset = offset,
            .speed = speed,
            .func = func,
            .time = -offset,
        };
    }

    pub fn reset(self: *Controller) void {
        self.time = -self.offset;
    }

    pub fn update(self: *Controller, dt: f32) f32 {
        self.time += self.speed * dt;
        const x = std.math.clamp(self.time, 0, 1);
        return self.func(x);
    }

    pub fn done(self: *Controller) bool {
        return self.time >= 1;
    }
};

pub const functions = struct {
    pub fn linear(x: f32) f32 {
        return x;
    }

    pub fn easeInQuad(x: f32) f32 {
        return x * x;
    }

    pub fn easeOutQuad(x: f32) f32 {
        return 1 - (1 - x) * (1 - x);
    }

    pub fn easeInOutQuad(x: f32) f32 {
        return if (x < 0.5) 2 * x * x else 1 - std.math.pow(f32, -2 * x + 2, 2) / 2;
    }

    pub fn easeInCubic(x: f32) f32 {
        return x * x * x;
    }

    pub fn easeOutCubic(x: f32) f32 {
        return 1 - std.math.pow(f32, 1 - x, 3);
    }

    pub fn easeInOutQuint(x: f32) f32 {
        return if (x < 0.5) 16 * x * x * x * x * x else 1 + 16 * std.math.pow(f32, x - 1, 5);
    }

    pub fn easeInBack(x: f32) f32 {
        const c1 = 1.70158;
        const c3 = c1 + 1;

        return c3 * x * x * x - c1 * x * x;
    }

    pub fn easeOutBack(x: f32) f32 {
        const c1 = 1.70158;
        const c3 = c1 + 1;

        return 1 + c3 * std.math.pow(f32, x - 1, 3) + c1 * std.math.pow(f32, x - 1, 2);
    }

    pub fn easeInOutElastic(x: f32) f32 {
        const c5: f32 = (2 * std.math.pi) / 4.5;

        if (x == 0) {
            return 0;
        } else if (x == 1) {
            return 1;
        } else if (x < 0.5) {
            return -(std.math.pow(f32, 2, 20 * x - 10) * std.math.sin((20 * x - 11.125) * c5)) / 2;
        } else {
            return (std.math.pow(f32, 2, -20 * x + 10) * std.math.sin((20 * x - 11.125) * c5)) / 2 + 1;
        }
    }

    pub fn reverse(comptime f: EasingFunction) EasingFunction {
        return struct {
            pub fn reverseFn(x: f32) f32 {
                return f(1 - x);
            }
        }.reverseFn;
    }

    pub fn amplify(comptime f: EasingFunction, comptime factor: f32) EasingFunction {
        return struct {
            pub fn amplifyFn(x: f32) f32 {
                return factor * f(x);
            }
        }.amplifyFn;
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
