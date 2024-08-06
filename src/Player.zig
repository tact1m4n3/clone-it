const std = @import("std");
const log = std.log.scoped(.player);
const Allocator = std.mem.Allocator;
const Timer = std.time.Timer;
const gl = @import("zgl");
const zlm = @import("zlm");

const animation = @import("animation.zig");
const Events = @import("Events.zig");
const Transform = @import("Transform.zig");
const ParticleSystem = @import("ParticleSystem.zig");

const Player = @This();

const State = union(enum) {
    idle,
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

const Vec3Interpolation = animation.Interpolate(zlm.Vec3);
const TransformInterpolation = animation.Interpolate(Transform);

state: State,
position: zlm.Vec3,
renderer: Renderer,

pub fn init(allocator: Allocator, position: zlm.Vec3, view_proj_matrix: zlm.Mat4) !Player {
    const renderer = try Renderer.init(allocator, view_proj_matrix);
    return .{
        .state = .idle,
        .position = position,
        .renderer = renderer,
    };
}

pub fn deinit(self: *Player) void {
    self.renderer.deinit();
}

pub fn update(self: *Player, dt: f32) void {
    var transform: Transform = .{};

    switch (self.state) {
        .idle => {
            transform.position = self.position;
        },
        .move => |*state| {
            const t = state.controller.update(dt);

            transform.position = state.animation.lerp(t);

            if (state.controller.done()) {
                self.state = .idle;
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
                                    .lerp_func = zlm.Vec3.lerp,
                                },
                                .scale_controller = animation.Controller.init(0, 1.4, animation.functions.easeOutBack),
                                .scale_animation = .{
                                    .initial_state = zlm.Vec3.zero,
                                    .final_state = zlm.Vec3.one,
                                    .lerp_func = zlm.Vec3.lerp,
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
                    self.state = .idle;
                }
            },
        },
    }

    transform.position.y += 0.5;

    self.renderer.model_matrix = transform.compute_matrix();
}

pub fn move(self: *Player, position: zlm.Vec3) bool {
    if (self.state != .idle) {
        return false;
    }

    self.state = .{
        .move = .{
            .controller = animation.Controller.init(0, 1.6, animation.functions.easeInOutElastic),
            .animation = .{
                .initial_state = self.position,
                .final_state = position,
                .lerp_func = zlm.Vec3.lerp,
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
                .particle_timer = Timer.start() catch unreachable, // this should never fail on a normal computer :))
                .position_controller = animation.Controller.init(0.6, 2.0, animation.functions.easeInCubic),
                .position_animation = .{
                    .initial_state = self.position,
                    .final_state = zlm.vec3(self.position.x, 8.0, self.position.z),
                    .lerp_func = zlm.Vec3.lerp,
                },
                .scale_controller = animation.Controller.init(0, 1.4, animation.functions.easeInBack),
                .scale_animation = .{
                    .initial_state = zlm.Vec3.one,
                    .final_state = zlm.Vec3.zero,
                    .lerp_func = zlm.Vec3.lerp,
                },
            },
        },
    };

    self.position = position;

    return true;
}

const Vertex = extern struct {
    position: zlm.Vec3,
    normal: zlm.Vec3,
};

const vertex_shader_path = "assets/shaders/player.vert.glsl";
const fragment_shader_path = "assets/shaders/player.frag.glsl";

// zig fmt: off
const player_vertices = [_]Vertex{
    .{ .position = zlm.vec3(-0.5, -0.5,  0.5), .normal = zlm.vec3( 0,  0,  1) },
    .{ .position = zlm.vec3( 0.5, -0.5,  0.5), .normal = zlm.vec3( 0,  0,  1) },
    .{ .position = zlm.vec3( 0.5,  0.5,  0.5), .normal = zlm.vec3( 0,  0,  1) },
    .{ .position = zlm.vec3(-0.5,  0.5,  0.5), .normal = zlm.vec3( 0,  0,  1) },

    .{ .position = zlm.vec3(-0.5, -0.5, -0.5), .normal = zlm.vec3( 0,  0, -1) },
    .{ .position = zlm.vec3( 0.5, -0.5, -0.5), .normal = zlm.vec3( 0,  0, -1) },
    .{ .position = zlm.vec3( 0.5,  0.5, -0.5), .normal = zlm.vec3( 0,  0, -1) },
    .{ .position = zlm.vec3(-0.5,  0.5, -0.5), .normal = zlm.vec3( 0,  0, -1) },

    .{ .position = zlm.vec3(-0.5, -0.5, -0.5), .normal = zlm.vec3(-1,  0,  0) },
    .{ .position = zlm.vec3(-0.5, -0.5,  0.5), .normal = zlm.vec3(-1,  0,  0) },
    .{ .position = zlm.vec3(-0.5,  0.5,  0.5), .normal = zlm.vec3(-1,  0,  0) },
    .{ .position = zlm.vec3(-0.5,  0.5, -0.5), .normal = zlm.vec3(-1,  0,  0) },

    .{ .position = zlm.vec3( 0.5, -0.5, -0.5), .normal = zlm.vec3( 1,  0,  0) },
    .{ .position = zlm.vec3( 0.5, -0.5,  0.5), .normal = zlm.vec3( 1,  0,  0) },
    .{ .position = zlm.vec3( 0.5,  0.5,  0.5), .normal = zlm.vec3( 1,  0,  0) },
    .{ .position = zlm.vec3( 0.5,  0.5, -0.5), .normal = zlm.vec3( 1,  0,  0) },

    .{ .position = zlm.vec3(-0.5,  0.5, -0.5), .normal = zlm.vec3( 0,  1,  0) },
    .{ .position = zlm.vec3(-0.5,  0.5,  0.5), .normal = zlm.vec3( 0,  1,  0) },
    .{ .position = zlm.vec3( 0.5,  0.5,  0.5), .normal = zlm.vec3( 0,  1,  0) },
    .{ .position = zlm.vec3( 0.5,  0.5, -0.5), .normal = zlm.vec3( 0,  1,  0) },

    .{ .position = zlm.vec3(-0.5, -0.5, -0.5), .normal = zlm.vec3( 0, -1,  0) },
    .{ .position = zlm.vec3(-0.5, -0.5,  0.5), .normal = zlm.vec3( 0, -1,  0) },
    .{ .position = zlm.vec3( 0.5, -0.5,  0.5), .normal = zlm.vec3( 0, -1,  0) },
    .{ .position = zlm.vec3( 0.5, -0.5, -0.5), .normal = zlm.vec3( 0, -1,  0) },
};
// zig fmt: on

const player_indices = create_indices: {
    var indices: [36]u8 = undefined;

    var offset: u32 = 0;
    var i: u32 = 0;
    while (i < indices.len) : ({
        i += 6;
        offset += 4;
    }) {
        indices[i + 0] = offset + 0;
        indices[i + 1] = offset + 1;
        indices[i + 2] = offset + 2;
        indices[i + 3] = offset + 2;
        indices[i + 4] = offset + 3;
        indices[i + 5] = offset + 0;
    }

    break :create_indices indices;
};

const Renderer = struct {
    view_proj_matrix: zlm.Mat4,
    model_matrix: zlm.Mat4,
    program: gl.Program,
    view_proj_matrix_uniform: u32,
    model_matrix_uniform: u32,
    vertex_array: gl.VertexArray,
    vertex_buffer: gl.Buffer,
    index_buffer: gl.Buffer,

    pub fn init(allocator: Allocator, view_proj_matrix: zlm.Mat4) !Renderer {
        const program = create_program: {
            const vertex_shader_source = @embedFile(vertex_shader_path);
            const fragment_shader_source = @embedFile(fragment_shader_path);

            const vertex_shader = gl.createShader(.vertex);
            defer gl.deleteShader(vertex_shader);

            gl.shaderSource(
                vertex_shader,
                1,
                &[_][]const u8{vertex_shader_source},
            );
            gl.compileShader(vertex_shader);

            if (gl.getShader(vertex_shader, .compile_status) == 0) {
                const info_log = try gl.getShaderInfoLog(vertex_shader, allocator);
                defer allocator.free(info_log);
                log.err("Vertex shader compile error: {s}", .{info_log});
                return error.VertexShaderCompileError;
            }

            const fragment_shader = gl.createShader(.fragment);
            defer gl.deleteShader(fragment_shader);

            gl.shaderSource(
                fragment_shader,
                1,
                &[_][]const u8{fragment_shader_source},
            );
            gl.compileShader(fragment_shader);
            if (gl.getShader(fragment_shader, .compile_status) == 0) {
                const info_log = try gl.getShaderInfoLog(fragment_shader, allocator);
                defer allocator.free(info_log);
                log.err("Fragment shader compile error: {s}", .{info_log});
                return error.FragmentShaderCompileError;
            }

            const program = gl.createProgram();
            errdefer gl.deleteProgram(program);

            gl.attachShader(program, vertex_shader);
            gl.attachShader(program, fragment_shader);
            gl.linkProgram(program);
            if (gl.getProgram(program, .link_status) == 0) {
                const info_log = try gl.getProgramInfoLog(program, allocator);
                defer allocator.free(info_log);
                log.err("Program link error: {s}", .{info_log});
                return error.ShaderCompileError;
            }

            break :create_program program;
        };

        const view_proj_matrix_uniform = gl.getUniformLocation(program, "u_ViewProjMatrix") orelse return error.UniformNotFound;
        const model_matrix_uniform = gl.getUniformLocation(program, "u_ModelMatrix") orelse return error.UniformNotFound;

        const vertex_array = gl.genVertexArray();
        const vertex_buffer = gl.genBuffer();
        const index_buffer = gl.genBuffer();

        {
            gl.bindVertexArray(vertex_array);
            defer gl.bindVertexArray(.invalid);

            {
                gl.bindBuffer(vertex_buffer, .array_buffer);
                defer gl.bindBuffer(.invalid, .array_buffer);

                gl.bufferData(.array_buffer, Vertex, &player_vertices, .static_draw);

                gl.enableVertexAttribArray(0);
                gl.vertexAttribPointer(
                    0,
                    3,
                    .float,
                    false,
                    @sizeOf(Vertex),
                    @offsetOf(Vertex, "position"),
                );

                gl.enableVertexAttribArray(1);
                gl.vertexAttribPointer(
                    1,
                    3,
                    .float,
                    false,
                    @sizeOf(Vertex),
                    @offsetOf(Vertex, "normal"),
                );
            }

            gl.bindBuffer(index_buffer, .element_array_buffer);
            gl.bufferData(.element_array_buffer, u8, &player_indices, .static_draw);
        }

        return .{
            .view_proj_matrix = view_proj_matrix,
            .model_matrix = zlm.Mat4.identity,
            .program = program,
            .view_proj_matrix_uniform = view_proj_matrix_uniform,
            .model_matrix_uniform = model_matrix_uniform,
            .vertex_array = vertex_array,
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
        };
    }

    pub fn deinit(renderer: *Renderer) void {
        gl.deleteBuffer(renderer.vertex_buffer);
        gl.deleteBuffer(renderer.index_buffer);
        gl.deleteVertexArray(renderer.vertex_array);
        gl.deleteProgram(renderer.program);
    }

    pub fn render(renderer: *Renderer) void {
        gl.useProgram(renderer.program);
        defer gl.useProgram(.invalid);

        gl.uniformMatrix4fv(renderer.view_proj_matrix_uniform, false, &[_][4][4]f32{renderer.view_proj_matrix.fields});
        gl.uniformMatrix4fv(renderer.model_matrix_uniform, false, &[_][4][4]f32{renderer.model_matrix.fields});

        gl.bindVertexArray(renderer.vertex_array);
        defer gl.bindVertexArray(.invalid);

        gl.drawElements(.triangles, player_indices.len, .unsigned_byte, 0);
    }
};
