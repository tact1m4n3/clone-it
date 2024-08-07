const std = @import("std");
const zlm = @import("zlm");
const zaudio = @import("zaudio");

const app = @import("app.zig");
const Event = app.Event;
const Text = @import("Text.zig");
const animation = @import("animation.zig");
const Transform = @import("Transform.zig");
const TextRenderer = @import("TextRenderer.zig");
const raycasting = @import("raycasting.zig");

const FloatInterpolation = animation.Interpolate(f32, struct {
    pub fn lerpFn(a: f32, b: f32, t: f32) f32 {
        return a + (b - a) * t;
    }
}.lerpFn);

pub const Button = struct {
    const State = union(enum) {
        idle,
        hover_in: struct {
            controller: animation.Controller,
            animation: FloatInterpolation,
        },
        click: struct {
            controller: animation.Controller,
            animation: FloatInterpolation,
        },
        hover_out: struct {
            controller: animation.Controller,
            animation: FloatInterpolation,
        },
    };

    text: Text,
    transform: Transform,
    color: zlm.Vec4,
    scale: f32 = 1,
    hovered: bool = false,
    state: State = .idle,

    pub fn init(text: Text, transform: Transform, color: zlm.Vec4) !Button {
        return .{
            .text = text,
            .transform = transform,
            .color = color,
        };
    }

    ///
    /// Returns true if the button is pressed.
    ///
    pub fn on_event(self: *Button, event: Event, view_proj_matrix: zlm.Mat4) bool {
        switch (event) {
            .cursor_pos => |pos| {
                const ray: raycasting.Ray = .{
                    .orig = zlm.vec3(0, 0, -1),
                    .dir = zlm.vec3(@floatCast(pos.x), @floatCast(pos.y), 1),
                };
                var bbox: raycasting.Bbox = .{
                    .min = zlm.vec3(self.text.rect.position.x, self.text.rect.position.y, 0),
                    .max = zlm.vec3(self.text.rect.position.x + self.text.rect.size.x, self.text.rect.position.y + self.text.rect.size.y, 0),
                };
                bbox = bbox.transform(zlm.Mat4.createUniformScale(self.scale).mul(self.transform.compute_matrix()).mul(view_proj_matrix));

                const intersects = ray.intersects(bbox);
                if (self.state == .idle and intersects) {
                    self.hovered = true;

                    self.state = .{
                        .hover_in = .{
                            .controller = animation.Controller.init(0, 8, animation.functions.linear),
                            .animation = .{
                                .initial_state = self.scale,
                                .final_state = 1.02,
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
                                .initial_state = self.scale,
                                .final_state = 0.95,
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

    pub fn update(self: *Button, dt: f32) void {
        switch (self.state) {
            .idle => {},
            .hover_in => |*state| {
                const t = state.controller.update(dt);
                self.scale = state.animation.lerp(t);

                if (!self.hovered) {
                    self.state = .{
                        .hover_out = .{
                            .controller = animation.Controller.init(0, 8, animation.functions.linear),
                            .animation = .{
                                .initial_state = self.scale,
                                .final_state = 1,
                            },
                        },
                    };
                }
            },
            .click => |*state| {
                const t = state.controller.update(dt);
                self.scale = state.animation.lerp(t);

                if (state.controller.done()) {
                    self.state = .{
                        .hover_in = .{
                            .controller = animation.Controller.init(0, 8, animation.functions.linear),
                            .animation = .{
                                .initial_state = self.scale,
                                .final_state = 1.02,
                            },
                        },
                    };
                }
            },
            .hover_out => |*state| {
                const t = state.controller.update(dt);
                self.scale = state.animation.lerp(t);

                if (state.controller.done())
                    self.state = .idle;
            },
        }
    }

    pub fn render(self: *Button, text_renderer: *TextRenderer, view_proj_matrix: zlm.Mat4) void {
        text_renderer.render(
            self.text,
            zlm.Mat4.createUniformScale(self.scale).mul(self.transform.compute_matrix()),
            view_proj_matrix,
            self.color,
        );
    }
};
