const std = @import("std");
const Allocator = std.mem.Allocator;
const gl = @import("zgl");
const zlm = @import("zlm");

const c = @import("c.zig");

const Font = @This();

// pub fn init(allocator: Allocator, audio_engine: *zaudio.Engine) !Assets {
//     var font = try Font.init(allocator);
//     errdefer font.deinit();
//     const background_sound = try Sound.init(audio_engine, "background.mp3", .{ .volume = 0.2, .loop = true });
//     const click_sound = try Sound.init(audio_engine, "click.mp3", .{});
//     return .{
//         .font = font,
//         .background_sound = background_sound,
//         .click_sound = click_sound,
//     };
// }
//
// pub fn deinit(self: *Assets) void {
//     self.font.deinit();
//     self.background_sound.deinit();
//     self.click_sound.deinit();
// }
//

// 0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~ 󰕾

pub const UvRect = struct {
    position: zlm.Vec2,
    size: zlm.Vec2,
};

pub const GlyphInfo = struct {
    advance: f32,

    offset: zlm.Vec2,
    size: zlm.Vec2,

    uv_rect: UvRect,
};

// chatgpt btw :))
const AutoGeneratedFontInfo = struct {
    pages: []const []const u8, // we don't use this
    chars: []const struct {
        id: i32,
        index: i32,
        char: []const u8,
        width: i32,
        height: i32,
        xoffset: i32,
        yoffset: i32,
        xadvance: i32,
        chnl: i32,
        x: i32,
        y: i32,
        page: i32,
    },
    info: struct {
        face: []const u8,
        size: i32,
        bold: i32,
        italic: i32,
        charset: []const []const u8,
        unicode: i32,
        stretchH: i32,
        smooth: i32,
        aa: i32,
        padding: []const i32,
        spacing: []const i32,
    },
    common: struct {
        lineHeight: i32,
        base: i32,
        scaleW: i32,
        scaleH: i32,
        pages: i32,
        @"packed": i32,
        alphaChnl: i32,
        redChnl: i32,
        greenChnl: i32,
        blueChnl: i32,
    },
    distanceField: struct {
        fieldType: []const u8,
        distanceRange: i32,
    },
};

const GlyphMap = std.AutoHashMap(u21, GlyphInfo);

allocator: Allocator,
atlas_texture: gl.Texture,
line_height: f32,
baseline: f32,
glyphs: GlyphMap,

pub fn init(allocator: Allocator) !Font {
    // ASSUME: only one page
    const info_data = @embedFile("assets/font/info.json");
    const atlas_data = @embedFile("assets/font/atlas.png");

    const info_parsed = try std.json.parseFromSlice(AutoGeneratedFontInfo, allocator, info_data, .{ .ignore_unknown_fields = true });
    defer info_parsed.deinit();
    const info = info_parsed.value;

    var atlas_width: c_int = undefined;
    var atlas_height: c_int = undefined;
    var atlas_channels: c_int = undefined;
    const atlas_pixels = c.stbi_load_from_memory(atlas_data.ptr, atlas_data.len, &atlas_width, &atlas_height, &atlas_channels, 4);
    defer c.stbi_image_free(atlas_pixels);
    std.debug.assert(atlas_pixels != null);
    std.debug.assert(atlas_channels == 4); // ASSUME: msdf

    const scale_factor = 1 / @as(f32, @floatFromInt(info.common.lineHeight));

    var glyphs = GlyphMap.init(allocator);

    for (info.chars) |glyph_info| {
        const ch = try std.unicode.utf8Decode(glyph_info.char);

        const width: f32 = @floatFromInt(glyph_info.width);
        const height: f32 = @floatFromInt(glyph_info.height);

        const offset = zlm.vec2(@floatFromInt(glyph_info.xoffset), @floatFromInt(glyph_info.yoffset)).scale(scale_factor);
        const size = zlm.vec2(width, height).scale(scale_factor);

        const atlas_size = zlm.vec2(@floatFromInt(atlas_width), @floatFromInt(atlas_height));
        const uv_rect: UvRect = .{
            .position = zlm.vec2(@floatFromInt(glyph_info.x), @floatFromInt(glyph_info.y)).div(atlas_size),
            .size = zlm.vec2(width, height).div(atlas_size),
        };

        try glyphs.put(ch, .{
            .advance = @as(f32, @floatFromInt(glyph_info.xadvance)) * scale_factor,

            .offset = offset,
            .size = size,

            .uv_rect = uv_rect,
        });
    }

    const atlas_texture = gl.genTexture();
    gl.bindTexture(atlas_texture, .@"2d");
    gl.texParameter(.@"2d", .min_filter, .nearest);
    gl.texParameter(.@"2d", .mag_filter, .linear);
    gl.textureImage2D(.@"2d", 0, .rgba, @intCast(atlas_width), @intCast(atlas_height), .rgba, .unsigned_byte, atlas_pixels);
    gl.bindTexture(.invalid, .@"2d");

    return .{
        .allocator = allocator,
        .atlas_texture = atlas_texture,
        .line_height = 1,
        .baseline = @as(f32, @floatFromInt(info.common.base)) * scale_factor,
        .glyphs = glyphs,
    };
}

pub fn deinit(self: *Font) void {
    gl.deleteTexture(self.atlas_texture);
    self.glyphs.deinit();
}
