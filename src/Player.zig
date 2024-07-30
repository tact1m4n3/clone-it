const std = @import("std");
const log = std.log.scoped(.player);
const Allocator = std.mem.Allocator;
const gl = @import("zgl");
const zlm = @import("zlm");

const animation = @import("animation.zig");
const Transform = @import("Transform.zig");

const Player = @This();

const State = enum {
    idle,
    moving,
};

const Vertex = extern struct {
    position: zlm.Vec3,
    normal: zlm.Vec3,
    id: f32,
};

const TransformInterpolation = animation.Interpolate(Transform);

const jump_animations = [3]TransformInterpolation{
    .{
        .initial_state = .{},
        .final_state = .{
            .position = zlm.vec3(0, 0.6, 0.15),
            .rotation = zlm.vec3(zlm.toRadians(10.0), 0, 0),
            .scale = zlm.Vec3.one,
        },
        .lerp_func = Transform.lerp,
    },
    .{
        .initial_state = .{},
        .final_state = .{
            .position = zlm.vec3(0, 1.2, 0.4),
            .rotation = zlm.vec3(zlm.toRadians(20.0), 0, 0),
            .scale = zlm.Vec3.one,
        },
        .lerp_func = Transform.lerp,
    },
    .{
        .initial_state = .{},
        .final_state = .{
            .position = zlm.vec3(0, 1.7, 0.8),
            .rotation = zlm.vec3(zlm.toRadians(30.0), 0, 0),
            .scale = zlm.Vec3.one,
        },
        .lerp_func = Transform.lerp,
    },
};

state: State,
anim_controller: animation.Controller,
jump_animations: [3]TransformInterpolation,
renderer: Renderer,

pub fn init(allocator: Allocator, view_proj_matrix: zlm.Mat4) !Player {
    const renderer = try Renderer.init(allocator, view_proj_matrix);
    return .{
        .state = .idle,
        .anim_controller = animation.Controller.init(1, animation.functions.easeOutCubic),
        .jump_animations = jump_animations,
        .renderer = renderer,
    };
}

pub fn deinit(self: *Player) void {
    self.renderer.deinit();
}

pub fn update(self: *Player, dt: f32) void {
    const t = self.anim_controller.update(dt);
    if (self.anim_controller.done()) self.anim_controller.reset();

    // animation
    var transforms = [3]Transform{
        jump_animations[0].lerp(t),
        jump_animations[1].lerp(t),
        jump_animations[2].lerp(t),
    };

    // move pieces in position
    inline for (&transforms) |*transform| {
        transform.scale.y *= 0.3;
    }
    transforms[1].position.y += 0.6;
    transforms[2].position.y += 1.2;

    inline for (transforms, 0..) |transform, i| {
        self.renderer.model_matrices[i] = transform.compute_matrix();
    }
}

const vertex_shader_path = "assets/shaders/player.vert.glsl";
const fragment_shader_path = "assets/shaders/player.frag.glsl";

// zig fmt: off
const cube_vertices = [_]Vertex{
    .{ .position = zlm.vec3(-1, -1,  1), .normal = zlm.vec3( 0,  0,  1), .id = 0 },
    .{ .position = zlm.vec3( 1, -1,  1), .normal = zlm.vec3( 0,  0,  1), .id = 0 },
    .{ .position = zlm.vec3( 1,  1,  1), .normal = zlm.vec3( 0,  0,  1), .id = 0 },
    .{ .position = zlm.vec3(-1,  1,  1), .normal = zlm.vec3( 0,  0,  1), .id = 0 },

    .{ .position = zlm.vec3(-1, -1, -1), .normal = zlm.vec3( 0,  0, -1), .id = 0 },
    .{ .position = zlm.vec3( 1, -1, -1), .normal = zlm.vec3( 0,  0, -1), .id = 0 },
    .{ .position = zlm.vec3( 1,  1, -1), .normal = zlm.vec3( 0,  0, -1), .id = 0 },
    .{ .position = zlm.vec3(-1,  1, -1), .normal = zlm.vec3( 0,  0, -1), .id = 0 },

    .{ .position = zlm.vec3(-1, -1, -1), .normal = zlm.vec3(-1,  0,  0), .id = 0 },
    .{ .position = zlm.vec3(-1, -1,  1), .normal = zlm.vec3(-1,  0,  0), .id = 0 },
    .{ .position = zlm.vec3(-1,  1,  1), .normal = zlm.vec3(-1,  0,  0), .id = 0 },
    .{ .position = zlm.vec3(-1,  1, -1), .normal = zlm.vec3(-1,  0,  0), .id = 0 },

    .{ .position = zlm.vec3( 1, -1, -1), .normal = zlm.vec3( 1,  0,  0), .id = 0 },
    .{ .position = zlm.vec3( 1, -1,  1), .normal = zlm.vec3( 1,  0,  0), .id = 0 },
    .{ .position = zlm.vec3( 1,  1,  1), .normal = zlm.vec3( 1,  0,  0), .id = 0 },
    .{ .position = zlm.vec3( 1,  1, -1), .normal = zlm.vec3( 1,  0,  0), .id = 0 },

    .{ .position = zlm.vec3(-1,  1, -1), .normal = zlm.vec3( 0,  1,  0), .id = 0 },
    .{ .position = zlm.vec3(-1,  1,  1), .normal = zlm.vec3( 0,  1,  0), .id = 0 },
    .{ .position = zlm.vec3( 1,  1,  1), .normal = zlm.vec3( 0,  1,  0), .id = 0 },
    .{ .position = zlm.vec3( 1,  1, -1), .normal = zlm.vec3( 0,  1,  0), .id = 0 },

    .{ .position = zlm.vec3(-1, -1, -1), .normal = zlm.vec3( 0, -1,  0), .id = 0 },
    .{ .position = zlm.vec3(-1, -1,  1), .normal = zlm.vec3( 0, -1,  0), .id = 0 },
    .{ .position = zlm.vec3( 1, -1,  1), .normal = zlm.vec3( 0, -1,  0), .id = 0 },
    .{ .position = zlm.vec3( 1, -1, -1), .normal = zlm.vec3( 0, -1,  0), .id = 0 },
};
// zig fmt: on

const player_vertices = create_vertices: {
    var vertices = cube_vertices ** 3;
    for (cube_vertices.len..cube_vertices.len * 2) |i| {
        vertices[i].id = 1;
    }
    for (cube_vertices.len * 2..cube_vertices.len * 3) |i| {
        vertices[i].id = 2;
    }
    break :create_vertices vertices;
};

const player_indices = create_indices: {
    var indices: [3 * 36]u8 = undefined;

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
    model_matrices: [3]zlm.Mat4,
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

                gl.enableVertexAttribArray(2);
                gl.vertexAttribPointer(
                    2,
                    1,
                    .float,
                    false,
                    @sizeOf(Vertex),
                    @offsetOf(Vertex, "id"),
                );
            }

            gl.bindBuffer(index_buffer, .element_array_buffer);
            gl.bufferData(.element_array_buffer, u8, &player_indices, .static_draw);
        }

        return .{
            .view_proj_matrix = view_proj_matrix,
            .model_matrices = [_]zlm.Mat4{zlm.Mat4.identity} ** 3,
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
        gl.uniformMatrix4fv(renderer.model_matrix_uniform, false, &[_][4][4]f32{
            renderer.model_matrices[0].fields,
            renderer.model_matrices[1].fields,
            renderer.model_matrices[2].fields,
        });

        gl.bindVertexArray(renderer.vertex_array);
        defer gl.bindVertexArray(.invalid);

        gl.drawElements(.triangles, player_indices.len, .unsigned_byte, 0);
    }
};
