const std = @import("std");
const gl = @import("zgl");
const zlm = @import("zlm");
const c = @import("c.zig");

const zlm_gl_float = zlm.SpecializeOn(gl.Float);
const Vec2 = zlm_gl_float.Vec2;
const Vec3 = zlm_gl_float.Vec3;

const zlm_gl_int = zlm.SpecializeOn(gl.Int);
const IVec2 = zlm_gl_int.Vec2;

const zlm_f64 = zlm.SpecializeOn(f64);

const app = @import("app.zig");
const Event = app.Event;

const World = @This();

rotation: struct {
    yaw: gl.Float,
    yaw_on_down: ?struct {
        relative: gl.Float,
        absolute: gl.Float,
    },
},
scale: gl.Float,

map: []const MapBlock,

grid_renderer: GridRenderer,
blocks_renderer: BlocksRenderer,

pub fn init(allocator: std.mem.Allocator) !World {
    const map: []const MapBlock = &[_]MapBlock{
        .{
            .kind = .testing,
            .position = .{ .x = 0, .y = 0 },
            .orientation = .rot0,
            .connections = .{
                .front = null,
                .back = null,
                .left = null,
                .right = null,
            },
        },
    };

    const grid_renderer = try GridRenderer.init();
    const blocks_renderer = try BlocksRenderer.init(map, allocator);

    return .{
        .rotation = .{
            .yaw = 3.0 / 8.0 * std.math.tau,
            .yaw_on_down = null,
        },
        .scale = -3.0,

        .map = map,

        .grid_renderer = grid_renderer,
        .blocks_renderer = blocks_renderer,
    };
}

pub fn deinit(self: World) void {
    self.blocks_renderer.deinit();
    self.grid_renderer.deinit();
}

fn mouseToYaw(mouse_position: zlm.Vec2, screen_width: usize, screen_height: usize) gl.Float {
    _ = screen_height;

    if (screen_width <= 1) {
        return 0.0;
    }

    return @floatCast((mouse_position.x / @as(f32, @floatFromInt(screen_width - 1)) * 2.0 - 1.0) * std.math.tau);
}

pub fn on_event(self: *World, event: Event) void {
    switch (event) {
        .mouse_button => |e| {
            if (e.button == .left and e.action == .press) {
                self.rotation.yaw_on_down = .{
                    .relative = @floatCast(app.getMousePosition().x * std.math.tau),
                    .absolute = self.rotation.yaw,
                };
            }

            if (e.button == .left and e.action == .release) {
                self.rotation.yaw_on_down = null;
            }
        },
        .mouse_scroll => |e| {
            self.scale += @floatCast(e.y / 5.0);
            self.scale = std.math.clamp(self.scale, -6.0, 0.0);
        },
        else => {},
    }
}

pub fn update(self: *World) void {
    if (self.rotation.yaw_on_down) |yaw_on_down| {
        const yaw_relative: f32 = @floatCast(app.getMousePosition().x * std.math.tau);
        self.rotation.yaw = yaw_on_down.absolute - (yaw_relative - yaw_on_down.relative);
    }
}

const BaseRenderer = struct {
    fn createShader(shader_type: gl.ShaderType, shader_src: []const u8) !gl.Shader {
        const shader = gl.createShader(shader_type);
        errdefer shader.delete();
        shader.source(1, &.{shader_src});
        shader.compile();

        if (shader.get(gl.ShaderParameter.compile_status) == gl.binding.FALSE) {
            var log: [std.mem.page_size]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&log);
            std.log.err("{s}", .{try shader.getCompileLog(fba.allocator())});
            return error.OpenGLShaderCompilationFailed;
        }

        return shader;
    }

    fn createProgram(vertex_shader_src: []const u8, fragment_shader_src: []const u8) !gl.Program {
        const vertex_shader = try createShader(gl.ShaderType.vertex, vertex_shader_src);
        defer vertex_shader.delete();

        const fragment_shader = try createShader(gl.ShaderType.fragment, fragment_shader_src);
        defer fragment_shader.delete();

        const program = gl.createProgram();
        errdefer program.delete();
        program.attach(vertex_shader);
        program.attach(fragment_shader);
        program.link();

        if (program.get(gl.ProgramParameter.link_status) == gl.binding.FALSE) {
            var log: [std.mem.page_size]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&log);
            std.log.err("{s}", .{try program.getCompileLog(fba.allocator())});
            return error.OpenGLProgramLinkFailed;
        }

        return program;
    }
};

const GridRenderer = struct {
    program: gl.Program,
    vao: gl.VertexArray,
    vbo: gl.Buffer,

    const Vertex = struct {
        position: Vec3,
    };

    const vertices = blk: {
        var _vertices: [2 * 2 * (16 + 1)]Vertex = undefined;

        for (0..16 + 1) |i| {
            _vertices[i * 4 + 0] = .{ .position = .{ .x = @floatFromInt(i), .y = 0.0, .z = 0.0 } };
            _vertices[i * 4 + 1] = .{ .position = .{ .x = @floatFromInt(i), .y = 16.0, .z = 0.0 } };

            _vertices[i * 4 + 2] = .{ .position = .{ .x = 0.0, .y = @floatFromInt(i), .z = 0.0 } };
            _vertices[i * 4 + 3] = .{ .position = .{ .x = 16.0, .y = @floatFromInt(i), .z = 0.0 } };
        }

        break :blk _vertices;
    };

    pub fn init() !GridRenderer {
        const program = try BaseRenderer.createProgram(@embedFile("assets/shaders/world_grid.vert.glsl"), @embedFile("assets/shaders/world_grid.frag.glsl"));
        const vao = gl.genVertexArray();
        const vbo = gl.genBuffer();

        return .{
            .program = program,
            .vao = vao,
            .vbo = vbo,
        };
    }

    pub fn deinit(self: GridRenderer) void {
        self.vbo.delete();
        self.vao.delete();
        self.program.delete();
    }

    pub fn uploadData(self: GridRenderer) void {
        self.vao.bind();

        self.vbo.bind(.array_buffer);
        gl.bufferData(.array_buffer, Vertex, &vertices, .static_draw);

        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 3, .float, false, @sizeOf(Vertex), @offsetOf(Vertex, "position"));
    }

    pub fn update(self: *const GridRenderer) void {
        const world: *const World = @alignCast(@fieldParentPtr("grid_renderer", self));

        const frame_buffer_size = app.getFramebufferSize();
        const aspect = @as(f32, @floatFromInt(frame_buffer_size[0])) / @as(f32, @floatFromInt(frame_buffer_size[1]));

        self.program.use();

        const screen_aspect_ratio_location = self.program.uniformLocation("screen_aspect_ratio") orelse @panic("TODO: Handle error!");
        self.program.uniform1f(screen_aspect_ratio_location, aspect);

        const world_scale_location = self.program.uniformLocation("world_scale") orelse @panic("TODO: Handle error!");
        self.program.uniform1f(world_scale_location, world.scale);

        const world_yaw_location = self.program.uniformLocation("world_yaw") orelse @panic("TODO: Handle error!");
        self.program.uniform1f(world_yaw_location, world.rotation.yaw);
    }

    pub fn render(self: GridRenderer) void {
        self.program.use();

        self.vao.bind();

        gl.drawArrays(.lines, 0, vertices.len);
    }
};

const BlocksRenderer = struct {
    program: gl.Program,
    block_atlas: gl.Texture,
    vaos: [std.meta.fields(BlockKind).len]gl.VertexArray,
    instance_vbos: [std.meta.fields(BlockKind).len]gl.Buffer,
    instance_ebos: [std.meta.fields(BlockKind).len]gl.Buffer,
    vbos: [std.meta.fields(BlockKind).len]gl.Buffer,
    render_map: RenderMap, // TODO: Rename these fields

    pub fn init(map: []const MapBlock, allocator: std.mem.Allocator) !BlocksRenderer {
        const program = try BaseRenderer.createProgram(@embedFile("assets/shaders/world.vert.glsl"), @embedFile("assets/shaders/world.frag.glsl"));

        const block_atlas = gl.genTexture();

        var vaos: [std.meta.fields(BlockKind).len]gl.VertexArray = undefined;
        var instance_vbos: [std.meta.fields(BlockKind).len]gl.Buffer = undefined;
        var instance_ebos: [std.meta.fields(BlockKind).len]gl.Buffer = undefined;
        var vbos: [std.meta.fields(BlockKind).len]gl.Buffer = undefined;

        gl.genVertexArrays(&vaos);
        gl.genBuffers(&instance_vbos);
        gl.genBuffers(&instance_ebos);
        gl.genBuffers(&vbos);

        const render_map = try mapToRender(map, allocator);

        return .{
            .program = program,
            .block_atlas = block_atlas,
            .vaos = vaos,
            .instance_vbos = instance_vbos,
            .instance_ebos = instance_ebos,
            .vbos = vbos,
            .render_map = render_map,
        };
    }

    pub fn deinit(self: BlocksRenderer) void {
        self.render_map.deinit();
        gl.deleteBuffers(&self.vbos);
        gl.deleteBuffers(&self.instance_ebos);
        gl.deleteBuffers(&self.instance_vbos);
        gl.deleteVertexArrays(&self.vaos);
        self.block_atlas.delete();
        self.program.delete();
    }

    pub fn uploadBlockAtlas(self: BlocksRenderer) void {
        var info: struct {
            width: c_int,
            height: c_int,
            num_channels: c_int,
        } = undefined;

        const src = @embedFile("assets/textures/block_atlas.png");

        c.stbi_set_flip_vertically_on_load(@intFromBool(true));

        const img = c.stbi_load_from_memory(src, src.len, &info.width, &info.height, &info.num_channels, 0) orelse @panic("TODO: Handle error!");
        defer c.stbi_image_free(img);

        std.debug.assert(info.num_channels == 4 and info.width >= 0 and info.height >= 0);

        gl.bindTexture(self.block_atlas, .@"2d");

        gl.texParameter(.@"2d", .min_filter, .nearest);
        gl.texParameter(.@"2d", .mag_filter, .nearest);
        gl.texParameter(.@"2d", .wrap_s, .clamp_to_edge);
        gl.texParameter(.@"2d", .wrap_t, .clamp_to_edge);

        gl.textureImage2D(
            .@"2d",
            0,
            .rgba8,
            @intCast(info.width),
            @intCast(info.height),
            .rgba,
            .unsigned_byte,
            img,
        );
    }

    pub fn uploadData(self: BlocksRenderer) void {
        inline for (std.meta.fields(BlockKind)) |kind| {
            self.vaos[kind.value].bind();

            self.instance_vbos[kind.value].bind(.array_buffer);
            gl.bufferData(.array_buffer, InstanceVertex, BlockKind.models[kind.value].vertices, .static_draw);

            self.instance_ebos[kind.value].bind(.element_array_buffer);
            gl.bufferData(.element_array_buffer, gl.UShort, BlockKind.models[kind.value].indices, .static_draw);

            self.vbos[kind.value].bind(.array_buffer);
            gl.bufferData(.array_buffer, RenderBlock, self.render_map.blocks[kind.value].items, .static_draw);

            gl.enableVertexAttribArray(0);
            gl.enableVertexAttribArray(1);
            gl.enableVertexAttribArray(2);
            gl.enableVertexAttribArray(3);
            gl.enableVertexAttribArray(4);

            gl.vertexAttribPointer(0, 3, .float, false, @sizeOf(InstanceVertex), @offsetOf(InstanceVertex, "position"));
            gl.vertexAttribPointer(1, 2, .float, false, @sizeOf(InstanceVertex), @offsetOf(InstanceVertex, "tex_coord"));
            gl.vertexAttribIPointer(2, 1, .unsigned_int, @sizeOf(InstanceVertex), @offsetOf(InstanceVertex, "face"));
            gl.vertexAttribIPointer(3, 2, .int, @sizeOf(RenderBlock), @offsetOf(RenderBlock, "position"));
            gl.vertexAttribDivisor(3, 1);
            gl.vertexAttribIPointer(4, 1, .unsigned_int, @sizeOf(RenderBlock), @offsetOf(RenderBlock, "orientation"));
            gl.vertexAttribDivisor(4, 1);
        }
    }

    pub fn update(self: *const BlocksRenderer) void {
        const world: *const World = @alignCast(@fieldParentPtr("blocks_renderer", self));

        const frame_buffer_size = app.getFramebufferSize();
        const aspect = @as(f32, @floatFromInt(frame_buffer_size[0])) / @as(f32, @floatFromInt(frame_buffer_size[1]));

        self.program.use();

        const screen_aspect_ratio_location = self.program.uniformLocation("screen_aspect_ratio") orelse @panic("TODO: Handle error!");
        self.program.uniform1f(screen_aspect_ratio_location, aspect);

        const world_scale_location = self.program.uniformLocation("world_scale") orelse @panic("TODO: Handle error!");
        self.program.uniform1f(world_scale_location, world.scale);

        const world_yaw_location = self.program.uniformLocation("world_yaw") orelse @panic("TODO: Handle error!");
        self.program.uniform1f(world_yaw_location, world.rotation.yaw);
    }

    pub fn render(self: BlocksRenderer) void {
        self.program.use();

        self.block_atlas.bind(.@"2d");

        inline for (std.meta.fields(BlockKind)) |kind| {
            if (self.render_map.blocks.len > 0) {
                const block_kind_location = self.program.uniformLocation("block_kind") orelse @panic("TODO: Handle error!");
                self.program.uniform1ui(block_kind_location, kind.value);

                self.vaos[kind.value].bind();

                gl.drawElementsInstanced(.triangles, BlockKind.models[kind.value].indices.len, .unsigned_short, 0, self.render_map.blocks[kind.value].items.len);
            }
        }
    }
};

const RenderMap = struct {
    blocks: [std.meta.fields(BlockKind).len]std.ArrayList(RenderBlock),

    pub fn init(allocator: std.mem.Allocator) RenderMap {
        var world: RenderMap = undefined;

        for (&world.blocks) |*block| {
            block.* = std.ArrayList(RenderBlock).init(allocator);
        }

        return world;
    }

    pub fn deinit(self: RenderMap) void {
        for (self.blocks) |block| {
            block.deinit();
        }
    }
};

const RenderBlock = struct {
    position: IVec2,
    orientation: BlockOrientation, // TODO: Extend this to general block data
};

const MapBlock = struct {
    kind: BlockKind,
    position: IVec2,
    orientation: BlockOrientation,
    connections: struct {
        front: ?usize, // -y
        back: ?usize, // +y
        left: ?usize, // -x
        right: ?usize, // +x
    },
};

const BlockKind = enum(gl.UInt) {
    testing = 0,
    wall = 1,
    floor = 2,
    source = 3,
    goal = 4,

    const cube = Model{
        .indices = blk2: {
            const _indices = blk3: {
                var _indices: [5 * 6]gl.UShort = undefined;
                for (0..5) |i| {
                    _indices[i * 6 + 0] = i * 4 + 0;
                    _indices[i * 6 + 1] = i * 4 + 1;
                    _indices[i * 6 + 2] = i * 4 + 2;
                    _indices[i * 6 + 3] = i * 4 + 2;
                    _indices[i * 6 + 4] = i * 4 + 3;
                    _indices[i * 6 + 5] = i * 4 + 0;
                }
                break :blk3 _indices;
            };
            break :blk2 &_indices;
        },
        .vertices = &[_]InstanceVertex{
            // Right (x = 0)
            .{ .position = .{ .x = -0.5, .y = 0.5, .z = -0.5 }, .tex_coord = .{ .x = 0.0, .y = 0.0 }, .face = .left },
            .{ .position = .{ .x = -0.5, .y = -0.5, .z = -0.5 }, .tex_coord = .{ .x = 1.0, .y = 0.0 }, .face = .left },
            .{ .position = .{ .x = -0.5, .y = -0.5, .z = 0.5 }, .tex_coord = .{ .x = 1.0, .y = 1.0 }, .face = .left },
            .{ .position = .{ .x = -0.5, .y = 0.5, .z = 0.5 }, .tex_coord = .{ .x = 0.0, .y = 1.0 }, .face = .left },
            // Right (x = 1)
            .{ .position = .{ .x = 0.5, .y = -0.5, .z = -0.5 }, .tex_coord = .{ .x = 0.0, .y = 0.0 }, .face = .right },
            .{ .position = .{ .x = 0.5, .y = 0.5, .z = -0.5 }, .tex_coord = .{ .x = 1.0, .y = 0.0 }, .face = .right },
            .{ .position = .{ .x = 0.5, .y = 0.5, .z = 0.5 }, .tex_coord = .{ .x = 1.0, .y = 1.0 }, .face = .right },
            .{ .position = .{ .x = 0.5, .y = -0.5, .z = 0.5 }, .tex_coord = .{ .x = 0.0, .y = 1.0 }, .face = .right },
            // Front (y = 0)
            .{ .position = .{ .x = -0.5, .y = -0.5, .z = -0.5 }, .tex_coord = .{ .x = 0.0, .y = 0.0 }, .face = .front },
            .{ .position = .{ .x = 0.5, .y = -0.5, .z = -0.5 }, .tex_coord = .{ .x = 1.0, .y = 0.0 }, .face = .front },
            .{ .position = .{ .x = 0.5, .y = -0.5, .z = 0.5 }, .tex_coord = .{ .x = 1.0, .y = 1.0 }, .face = .front },
            .{ .position = .{ .x = -0.5, .y = -0.5, .z = 0.5 }, .tex_coord = .{ .x = 0.0, .y = 1.0 }, .face = .front },
            // Back (y = 1)
            .{ .position = .{ .x = 0.5, .y = 0.5, .z = -0.5 }, .tex_coord = .{ .x = 0.0, .y = 0.0 }, .face = .back },
            .{ .position = .{ .x = -0.5, .y = 0.5, .z = -0.5 }, .tex_coord = .{ .x = 1.0, .y = 0.0 }, .face = .back },
            .{ .position = .{ .x = -0.5, .y = 0.5, .z = 0.5 }, .tex_coord = .{ .x = 1.0, .y = 1.0 }, .face = .back },
            .{ .position = .{ .x = 0.5, .y = 0.5, .z = 0.5 }, .tex_coord = .{ .x = 0.0, .y = 1.0 }, .face = .back },
            // Top (z = 1)
            .{ .position = .{ .x = -0.5, .y = -0.5, .z = 0.5 }, .tex_coord = .{ .x = 0.0, .y = 0.0 }, .face = .top },
            .{ .position = .{ .x = 0.5, .y = -0.5, .z = 0.5 }, .tex_coord = .{ .x = 1.0, .y = 0.0 }, .face = .top },
            .{ .position = .{ .x = 0.5, .y = 0.5, .z = 0.5 }, .tex_coord = .{ .x = 1.0, .y = 1.0 }, .face = .top },
            .{ .position = .{ .x = -0.5, .y = 0.5, .z = 0.5 }, .tex_coord = .{ .x = 0.0, .y = 1.0 }, .face = .top },
        },
    };

    pub const models = [std.meta.fields(BlockKind).len]Model{
        cube,
        cube,
        cube,
        cube,
        cube,
    };

    const Model = struct { indices: []const gl.UShort, vertices: []const InstanceVertex };
};

const InstanceVertex = struct {
    position: Vec3,
    tex_coord: Vec2,
    face: BlockFace, // TODO: SoA this B
};

const BlockFace = enum(gl.UInt) {
    left = 0, // x = 0
    right = 1, // x = 1
    front = 2, // y = 0
    back = 3, // y = 1
    top = 4, // z = 1
};

const BlockOrientation = enum(gl.UInt) {
    rot0 = 0,
    rot90 = 1,
    rot180 = 2,
    rot270 = 3,
};

fn mapToRender(map: []const MapBlock, allocator: std.mem.Allocator) std.mem.Allocator.Error!RenderMap {
    var render_world: RenderMap = RenderMap.init(allocator);
    errdefer render_world.deinit();

    for (map) |map_block| {
        try render_world.blocks[@intFromEnum(map_block.kind)].append(.{
            .position = map_block.position,
            .orientation = map_block.orientation,
        });
    }

    return render_world;
}
