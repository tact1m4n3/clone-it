const std = @import("std");
const log = std.log.scoped(.particle_renderer);
const Allocator = std.mem.Allocator;
const gl = @import("zgl");
const zlm = @import("zlm");

const Self = @This();

const Vertex = extern struct {
    position: zlm.Vec3,
    normal: zlm.Vec3,
};

const InstanceData = extern struct {
    color: zlm.Vec4,
    model_matrix: zlm.Mat4,
};

const UniformData = extern struct {
    view_proj_matrix: zlm.Mat4,
    instances: [max_cubes]InstanceData,
};

const vertex_shader_path = "shaders/particle.vert.glsl";
const fragment_shader_path = "shaders/particle.frag.glsl";

const max_cubes = 100;

// TODO: maybe come up with a compile time solution
// zig fmt: off
const cube_vertices = [_]Vertex{
    .{ .position = zlm.vec3(-1, -1,  1), .normal = zlm.vec3( 0,  0,  1) },
    .{ .position = zlm.vec3( 1, -1,  1), .normal = zlm.vec3( 0,  0,  1) },
    .{ .position = zlm.vec3( 1,  1,  1), .normal = zlm.vec3( 0,  0,  1) },
    .{ .position = zlm.vec3(-1,  1,  1), .normal = zlm.vec3( 0,  0,  1) },

    .{ .position = zlm.vec3(-1, -1, -1), .normal = zlm.vec3( 0,  0, -1) },
    .{ .position = zlm.vec3( 1, -1, -1), .normal = zlm.vec3( 0,  0, -1) },
    .{ .position = zlm.vec3( 1,  1, -1), .normal = zlm.vec3( 0,  0, -1) },
    .{ .position = zlm.vec3(-1,  1, -1), .normal = zlm.vec3( 0,  0, -1) },

    .{ .position = zlm.vec3(-1, -1, -1), .normal = zlm.vec3(-1,  0,  0) },
    .{ .position = zlm.vec3(-1, -1,  1), .normal = zlm.vec3(-1,  0,  0) },
    .{ .position = zlm.vec3(-1,  1,  1), .normal = zlm.vec3(-1,  0,  0) },
    .{ .position = zlm.vec3(-1,  1, -1), .normal = zlm.vec3(-1,  0,  0) },

    .{ .position = zlm.vec3( 1, -1, -1), .normal = zlm.vec3( 1,  0,  0) },
    .{ .position = zlm.vec3( 1, -1,  1), .normal = zlm.vec3( 1,  0,  0) },
    .{ .position = zlm.vec3( 1,  1,  1), .normal = zlm.vec3( 1,  0,  0) },
    .{ .position = zlm.vec3( 1,  1, -1), .normal = zlm.vec3( 1,  0,  0) },

    .{ .position = zlm.vec3(-1,  1, -1), .normal = zlm.vec3( 0,  1,  0) },
    .{ .position = zlm.vec3(-1,  1,  1), .normal = zlm.vec3( 0,  1,  0) },
    .{ .position = zlm.vec3( 1,  1,  1), .normal = zlm.vec3( 0,  1,  0) },
    .{ .position = zlm.vec3( 1,  1, -1), .normal = zlm.vec3( 0,  1,  0) },

    .{ .position = zlm.vec3(-1, -1, -1), .normal = zlm.vec3( 0, -1,  0) },
    .{ .position = zlm.vec3(-1, -1,  1), .normal = zlm.vec3( 0, -1,  0) },
    .{ .position = zlm.vec3( 1, -1,  1), .normal = zlm.vec3( 0, -1,  0) },
    .{ .position = zlm.vec3( 1, -1, -1), .normal = zlm.vec3( 0, -1,  0) },
};
// zig fmt: on

const cube_indices = create_indices: {
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

allocator: Allocator,
view_proj_matrix: zlm.Mat4,
program: gl.Program,
uniform_data: *UniformData,
instance_count: usize,
vertex_array: gl.VertexArray,
vertex_buffer: gl.Buffer,
index_buffer: gl.Buffer,
uniform_buffer: gl.Buffer,

pub fn init(allocator: Allocator, view_proj_matrix: zlm.Mat4) !Self {
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

    const uniform_data_index: u32 = @intCast(gl.binding.getUniformBlockIndex(@intFromEnum(program), "UniformData"));
    gl.uniformBlockBinding(program, uniform_data_index, 0);

    const uniform_data = try allocator.create(UniformData);

    const vertex_array = gl.genVertexArray();
    const vertex_buffer = gl.genBuffer();
    const index_buffer = gl.genBuffer();
    const uniform_buffer = gl.genBuffer();

    {
        gl.bindVertexArray(vertex_array);
        defer gl.bindVertexArray(.invalid);

        {
            gl.bindBuffer(vertex_buffer, .array_buffer);
            defer gl.bindBuffer(.invalid, .array_buffer);

            gl.bufferData(.array_buffer, Vertex, &cube_vertices, .static_draw);

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
        gl.bufferData(.element_array_buffer, u8, &cube_indices, .static_draw);
    }

    {
        gl.bindBuffer(uniform_buffer, .uniform_buffer);
        defer gl.bindBuffer(.invalid, .uniform_buffer);

        gl.bufferUninitialized(.uniform_buffer, UniformData, 1, .dynamic_draw);
    }

    return .{
        .allocator = allocator,
        .view_proj_matrix = view_proj_matrix,
        .program = program,
        .uniform_data = uniform_data,
        .instance_count = 0,
        .vertex_array = vertex_array,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .uniform_buffer = uniform_buffer,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.destroy(self.uniform_data);
    gl.deleteBuffer(self.uniform_buffer);
    gl.deleteBuffer(self.vertex_buffer);
    gl.deleteBuffer(self.index_buffer);
    gl.deleteVertexArray(self.vertex_array);
    gl.deleteProgram(self.program);
}

pub fn render(self: *Self, model_matrix: zlm.Mat4, color: zlm.Vec4) void {
    if (self.instance_count >= max_cubes) {
        self.flush();
    }

    self.uniform_data.instances[self.instance_count].model_matrix = model_matrix;
    self.uniform_data.instances[self.instance_count].color = color;
    self.instance_count += 1;
}

pub fn flush(self: *Self) void {
    if (self.instance_count == 0) {
        return;
    }

    {
        self.uniform_data.view_proj_matrix = self.view_proj_matrix;

        gl.bindBuffer(self.uniform_buffer, .uniform_buffer);
        defer gl.bindBuffer(.invalid, .uniform_buffer);

        gl.bufferSubData(.uniform_buffer, 0, UniformData, self.uniform_data[0..1]);
    }

    gl.useProgram(self.program);
    defer gl.useProgram(.invalid);

    gl.bindVertexArray(self.vertex_array);
    defer gl.bindVertexArray(.invalid);

    gl.bindBufferBase(.uniform_buffer, 0, self.uniform_buffer);

    gl.drawElementsInstanced(.triangles, cube_indices.len, .unsigned_byte, 0, self.instance_count);

    self.instance_count = 0;
}
