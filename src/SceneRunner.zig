const std = @import("std");
const log = std.log.scoped(.scene_renderer);
const Allocator = std.mem.Allocator;
const gl = @import("zgl");
const zlm = @import("zlm");

const app = @import("app.zig");
const Event = app.Event;
const Scene = @import("Scene.zig");
const animation = @import("animation.zig");

const SceneRunner = @This();

const FloatInterpolation = animation.Interpolate(f32, struct {
    pub fn lerpFn(a: f32, b: f32, t: f32) f32 {
        return a + (b - a) * t;
    }
}.lerpFn);

const State = union(enum) {
    intro: struct {
        controller: animation.Controller,
        animation: FloatInterpolation,
    },
    play,
    outro: struct {
        controller: animation.Controller,
        animation: FloatInterpolation,
    },
};

const Vertex = extern struct {
    position: zlm.Vec2,
    tex_coord: zlm.Vec2,
};

const vertex_shader_path = "assets/shaders/blit.vert.glsl";
const fragment_shader_path = "assets/shaders/blit.frag.glsl";

// zig fmt: off
const quad_vertices = [_]Vertex{
    .{ .position = zlm.vec2(-1, -1), .tex_coord = zlm.vec2(0, 0) },
    .{ .position = zlm.vec2( 1, -1), .tex_coord = zlm.vec2(1, 0) },
    .{ .position = zlm.vec2( 1,  1), .tex_coord = zlm.vec2(1, 1) },
    .{ .position = zlm.vec2(-1,  1), .tex_coord = zlm.vec2(0, 1) },
};
// zig fmt: on

const quad_indices = [_]u8{
    0, 1, 2, 2, 3, 0,
};

state: State,
transparency: f32,
scene: Scene,
next_scene: ?Scene,
program: gl.Program,
transparency_uniform: u32,
vertex_array: gl.VertexArray,
vertex_buffer: gl.Buffer,
index_buffer: gl.Buffer,
frame_buffer: gl.Framebuffer,
texture: gl.Texture,
render_buffer: gl.Renderbuffer,

pub fn init(allocator: Allocator, scene: Scene) !SceneRunner {
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
    errdefer gl.deleteProgram(program);

    const transparency_uniform = gl.getUniformLocation(program, "u_Transparency") orelse return error.UniformNotFound;

    const vertex_array = gl.genVertexArray();
    const vertex_buffer = gl.genBuffer();
    const index_buffer = gl.genBuffer();

    {
        gl.bindVertexArray(vertex_array);
        defer gl.bindVertexArray(.invalid);

        {
            gl.bindBuffer(vertex_buffer, .array_buffer);
            defer gl.bindBuffer(.invalid, .array_buffer);

            gl.bufferData(.array_buffer, Vertex, &quad_vertices, .static_draw);

            gl.enableVertexAttribArray(0);
            gl.vertexAttribPointer(
                0,
                2,
                .float,
                false,
                @sizeOf(Vertex),
                @offsetOf(Vertex, "position"),
            );

            gl.enableVertexAttribArray(1);
            gl.vertexAttribPointer(
                1,
                2,
                .float,
                false,
                @sizeOf(Vertex),
                @offsetOf(Vertex, "tex_coord"),
            );
        }

        gl.bindBuffer(index_buffer, .element_array_buffer);
        gl.bufferData(.element_array_buffer, u8, &quad_indices, .static_draw);
    }

    const frame_buffer_size = app.getFramebufferSize();

    const frame_buffer = gl.genFramebuffer();
    const texture = gl.genTexture();
    const render_buffer = gl.genRenderbuffer();
    {
        gl.bindFramebuffer(frame_buffer, .buffer);
        defer gl.bindFramebuffer(.invalid, .buffer);

        {
            gl.bindTexture(texture, .@"2d_multisample");
            defer gl.bindTexture(.invalid, .@"2d_multisample");

            gl.binding.texImage2DMultisample(
                gl.binding.TEXTURE_2D_MULTISAMPLE,
                4,
                gl.binding.RGB,
                @intCast(frame_buffer_size[0]),
                @intCast(frame_buffer_size[1]),
                gl.binding.TRUE,
            );

            gl.framebufferTexture2D(frame_buffer, .buffer, .color0, .@"2d_multisample", texture, 0);
        }

        {
            gl.bindRenderbuffer(render_buffer, .buffer);
            defer gl.bindRenderbuffer(.invalid, .buffer);

            gl.binding.renderbufferStorageMultisample(
                gl.binding.RENDERBUFFER,
                4,
                gl.binding.DEPTH24_STENCIL8,
                @intCast(frame_buffer_size[0]),
                @intCast(frame_buffer_size[1]),
            );

            gl.framebufferRenderbuffer(
                frame_buffer,
                .buffer,
                .depth_stencil,
                .buffer,
                render_buffer,
            );
        }
    }

    return .{
        .state = .{
            .intro = .{
                .controller = animation.Controller.init(0.0, 1.0, animation.functions.easeOutQuad),
                .animation = .{
                    .initial_state = 0,
                    .final_state = 1,
                },
            },
        },
        .transparency = 0,
        .scene = scene,
        .next_scene = null,
        .program = program,
        .transparency_uniform = transparency_uniform,
        .vertex_array = vertex_array,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .frame_buffer = frame_buffer,
        .texture = texture,
        .render_buffer = render_buffer,
    };
}

pub fn deinit(self: *SceneRunner) void {
    gl.deleteProgram(self.program);
    gl.deleteVertexArray(self.vertex_array);
    gl.deleteBuffer(self.vertex_buffer);
    gl.deleteBuffer(self.index_buffer);
    gl.deleteFramebuffer(self.frame_buffer);
    gl.deleteTexture(self.texture);
    gl.deleteRenderbuffer(self.render_buffer);
}

pub fn on_event(self: *SceneRunner, event: Event) void {
    // maybe we should handle events only after fade in
    self.scene.on_event(event);
}

pub fn update(self: *SceneRunner, dt: f32) void {
    switch (self.state) {
        .intro => |*state| {
            const t = state.controller.update(dt);
            self.transparency = state.animation.lerp(t);

            if (state.controller.done()) {
                self.state = .play;
            }
        },
        .play => self.transparency = 1,
        .outro => |*state| {
            const t = state.controller.update(dt);
            self.transparency = state.animation.lerp(t);

            if (state.controller.done()) {
                self.state = .{
                    .intro = .{
                        .controller = animation.Controller.init(0, 1, animation.functions.easeOutQuad),
                        .animation = .{
                            .initial_state = 0,
                            .final_state = 1,
                        },
                    },
                };
                self.scene = self.next_scene.?;
                self.next_scene = null;
            }
        },
    }

    self.scene.update(dt);
}

pub fn render(self: *SceneRunner) void {
    gl.enable(.blend);
    defer gl.disable(.blend);
    gl.blendFunc(.src_alpha, .one_minus_src_alpha);

    {
        gl.enable(.depth_test);
        defer gl.disable(.depth_test);

        gl.bindFramebuffer(self.frame_buffer, .buffer);
        defer gl.bindFramebuffer(.invalid, .buffer);

        self.scene.render();
    }

    {
        gl.bindFramebuffer(.invalid, .buffer);

        gl.clearColor(0, 0, 0, 0);
        gl.clear(.{ .color = true });

        gl.useProgram(self.program);
        defer gl.useProgram(.invalid);

        gl.uniform1f(self.transparency_uniform, self.transparency);
        gl.bindTexture(self.texture, .@"2d_multisample");

        gl.bindVertexArray(self.vertex_array);
        defer gl.bindVertexArray(.invalid);

        gl.drawElements(.triangles, quad_indices.len, .unsigned_byte, 0);
    }
}

pub fn change_scene(self: *SceneRunner, scene: Scene) void {
    self.next_scene = scene;
    self.state = .{
        .outro = .{
            .controller = animation.Controller.init(0, 1, animation.functions.easeInQuad),
            .animation = .{
                .initial_state = self.transparency,
                .final_state = 0,
            },
        },
    };
}
