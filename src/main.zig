const std = @import("std");
const c = @import("c.zig");
const gl = @import("zgl");
const zlm = @import("zlm");

const Window = @import("Window.zig");
const Events = @import("Events.zig");
const Font = @import("Font.zig");
const Transform = @import("Transform.zig");
const TextRenderer = @import("TextRenderer.zig");
const ParticleRenderer = @import("ParticleRenderer.zig");
const Player = @import("Player.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const window = try Window.init(.{
        .width = 1280,
        .height = 720,
        .title = "Hello title",
    });
    defer window.deinit();

    const events = Events.init(window);

    // idk if we should leave these here
    {
        try gl.loadExtensions(0, struct {
            pub fn getProc(comptime _: comptime_int, name: [:0]const u8) ?*align(4) const anyopaque {
                if (c.glfwGetProcAddress(name)) |func| {
                    return func;
                } else {
                    return @ptrCast(&struct {
                        pub fn procNotFound() callconv(.C) noreturn {
                            @panic("opengl function not supported");
                        }
                    }.procNotFound);
                }
            }
        }.getProc);

        gl.enable(.blend);
        gl.blendFunc(.src_alpha, .one_minus_src_alpha);

        gl.enable(.depth_test);
        gl.depthFunc(.less);
    }

    const aspect = 1280.0 / 720.0;
    // var proj_matrix = zlm.Mat4.createPerspective(zlm.toRadians(45.0), aspect, 0.1, 1000);
    var proj_matrix = zlm.Mat4.createOrthogonal(3 * -aspect, 3 * aspect, -3, 3, -1000, 1000);
    const view_matrix = zlm.Mat4.createLookAt(zlm.vec3(8, 4, 8), zlm.vec3(0, 1, 0), zlm.vec3(0, 1, 0));
    var view_proj_matrix = view_matrix.mul(proj_matrix);

    var font = try Font.init(allocator, "anonymous_pro");
    defer font.deinit();
    var text_renderer = try TextRenderer.init(allocator, &font, view_proj_matrix);
    defer text_renderer.deinit();

    var particle_renderer = try ParticleRenderer.init(allocator, view_proj_matrix);
    defer particle_renderer.deinit();

    var player = try Player.init(allocator, zlm.vec3(0, 0, -8), view_proj_matrix);
    defer player.deinit();

    var timer = try std.time.Timer.start();

    while (!window.shouldClose()) {
        events.reset();
        window.pollEvents();

        // update
        {
            const dt = @as(f32, @floatFromInt(timer.lap())) / @as(f32, @floatFromInt(std.time.ns_per_s));

            if (events.resized()) |size| {
                const new_aspect = @as(f32, @floatFromInt(size[0])) / @as(f32, @floatFromInt(size[1]));
                proj_matrix = zlm.Mat4.createOrthogonal(-new_aspect, new_aspect, -1, 1, -1000, 1000);
                view_proj_matrix = view_matrix.mul(proj_matrix);
                text_renderer.view_proj_matrix = view_proj_matrix;
                particle_renderer.view_proj_matrix = view_proj_matrix;
                player.renderer.view_proj_matrix = view_proj_matrix;
            }

            player.update(dt, events);
        }

        // render
        {
            gl.clearColor(0, 0, 0, 0);
            gl.clear(.{ .color = true, .depth = true });

            // renderer.render("Hello", zlm.Mat4.identity, zlm.Vec4.one);
            // renderer.flush();
            // const floor_transform: Transform = .{ .position = zlm.vec3(0, -0.1, 0), .scale = zlm.vec3(100.0, 0.01, 100.0) };
            // particle_renderer.render(floor_transform.compute_matrix(), zlm.vec4(0.6, 0.4, 0.4, 1.0));
            // particle_renderer.flush();

            player.renderer.render();
        }

        window.swapBuffers();
    }
}
