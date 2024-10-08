const std = @import("std");

const log = std.log.scoped(.text_renderer);
const Allocator = std.mem.Allocator;
const gl = @import("zgl");
const zlm = @import("zlm");

const app = @import("app.zig");
const Text = @import("Text.zig");

const TextRenderer = @This();

const Vertex = extern struct {
    position: zlm.Vec4,
    color: zlm.Vec4,
    tex_coord: zlm.Vec2,
};

const max_quads = 2000;
const max_vertices = max_quads * 4;
const max_indices = max_quads * 6;

const vertex_shader_path = "assets/shaders/text.vert.glsl";
const fragment_shader_path = "assets/shaders/text.frag.glsl";

const quad_positions = [_]zlm.Vec2{
    .{ .x = 0, .y = 0 },
    .{ .x = 0, .y = -1 },
    .{ .x = 1, .y = -1 },
    .{ .x = 1, .y = 0 },
};

const quad_tex_coords = [_]zlm.Vec2{
    .{ .x = 0, .y = 0 },
    .{ .x = 0, .y = 1 },
    .{ .x = 1, .y = 1 },
    .{ .x = 1, .y = 0 },
};

allocator: Allocator,
vertices: []Vertex,
vertex_count: u16,
index_count: u16,
program: gl.Program,
view_proj_matrix_uniform: u32,
vertex_array: gl.VertexArray,
vertex_buffer: gl.Buffer,
index_buffer: gl.Buffer,
atlas_texture: ?gl.Texture,

pub fn init(allocator: Allocator) !TextRenderer {
    const vertices = try allocator.alloc(Vertex, max_vertices);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u16, max_indices);
    defer allocator.free(indices);

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
            return error.ShaderCompileError;
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
            return error.ShaderCompileError;
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
    errdefer gl.deleteProgram(program);

    const view_proj_matrix_uniform = gl.getUniformLocation(program, "u_ViewProjMatrix") orelse return error.UniformNotFound;

    const vertex_array = gl.genVertexArray();
    const vertex_buffer = gl.genBuffer();
    const index_buffer = gl.genBuffer();

    {
        var i: u16 = 0;
        var offset: u16 = 0;
        while (i < max_indices) : ({
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
    }

    {
        gl.bindVertexArray(vertex_array);
        defer gl.bindVertexArray(.invalid);

        {
            gl.bindBuffer(vertex_buffer, .array_buffer);
            defer gl.bindBuffer(.invalid, .array_buffer);

            gl.bufferUninitialized(.array_buffer, Vertex, max_vertices, .dynamic_draw);

            gl.enableVertexAttribArray(0);
            gl.vertexAttribPointer(
                0,
                4,
                .float,
                false,
                @sizeOf(Vertex),
                @offsetOf(Vertex, "position"),
            );

            gl.enableVertexAttribArray(1);
            gl.vertexAttribPointer(
                1,
                4,
                .float,
                false,
                @sizeOf(Vertex),
                @offsetOf(Vertex, "color"),
            );

            gl.enableVertexAttribArray(2);
            gl.vertexAttribPointer(
                2,
                2,
                .float,
                false,
                @sizeOf(Vertex),
                @offsetOf(Vertex, "tex_coord"),
            );
        }

        gl.bindBuffer(index_buffer, .element_array_buffer);
        gl.bufferData(.element_array_buffer, u16, indices, .static_draw);
    }

    return .{
        .allocator = allocator,
        .vertices = vertices,
        .vertex_count = 0,
        .index_count = 0,
        .program = program,
        .view_proj_matrix_uniform = view_proj_matrix_uniform,
        .vertex_array = vertex_array,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .atlas_texture = null,
    };
}

pub fn deinit(self: *TextRenderer) void {
    self.allocator.free(self.vertices);
    gl.deleteBuffer(self.vertex_buffer);
    gl.deleteBuffer(self.index_buffer);
    gl.deleteVertexArray(self.vertex_array);
    gl.deleteProgram(self.program);
}

pub fn render(self: *TextRenderer, text: Text, model_matrix: zlm.Mat4, view_proj_matrix: zlm.Mat4, color: zlm.Vec4) void {
    if (text.str.len == 0)
        return;

    const font = &app.state.font;

    if (self.atlas_texture != font.atlas_texture)
        self.flush(view_proj_matrix);

    self.atlas_texture = font.atlas_texture;

    var position = zlm.vec2(text.rect.position.x, text.rect.position.y + text.rect.size.y + font.line_height - font.baseline);

    const view = std.unicode.Utf8View.initUnchecked(text.str);
    var iter = view.iterator();
    while (iter.nextCodepoint()) |ch| {
        if (ch == '\n') {
            position.x = text.rect.position.x;
            position.y -= font.line_height;
            continue;
        }

        if (self.vertex_count + 4 > max_vertices) {
            self.flush(view_proj_matrix);
        }

        const glyph_info = font.glyphs.get(ch).?;

        const quad_position = position.add(.{ .x = glyph_info.offset.x, .y = -glyph_info.offset.y });
        const quad_size = glyph_info.size;

        inline for (quad_positions, quad_tex_coords, 0..) |local_position, tex_coord, i| {
            const vertex_position = quad_position.add(quad_size.mul(local_position));
            self.vertices[self.vertex_count + i] = .{
                .position = zlm.vec4(vertex_position.x, vertex_position.y, 0, 1).transform(model_matrix),
                .color = color,
                .tex_coord = glyph_info.uv_rect.position.add(glyph_info.uv_rect.size.mul(tex_coord)),
            };
        }

        position.x += glyph_info.advance;

        self.vertex_count += 4;
        self.index_count += 6;
    }
}

pub fn flush(self: *TextRenderer, view_proj_matrix: zlm.Mat4) void {
    if (self.index_count == 0 or self.atlas_texture == null) {
        return;
    }

    {
        gl.bindBuffer(self.vertex_buffer, .array_buffer);
        defer gl.bindBuffer(.invalid, .array_buffer);

        gl.bufferSubData(.array_buffer, 0, Vertex, self.vertices[0..self.vertex_count]);
    }

    gl.useProgram(self.program);
    defer gl.useProgram(.invalid);

    gl.uniformMatrix4fv(self.view_proj_matrix_uniform, false, &[_][4][4]f32{view_proj_matrix.fields});
    gl.bindTexture(self.atlas_texture.?, .@"2d");

    gl.bindVertexArray(self.vertex_array);
    defer gl.bindVertexArray(.invalid);

    gl.drawElements(.triangles, self.index_count, .unsigned_short, 0);

    self.vertex_count = 0;
    self.index_count = 0;
    self.atlas_texture = null;
}
