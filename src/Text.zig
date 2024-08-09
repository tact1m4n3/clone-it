const std = @import("std");
const zlm = @import("zlm");

const app = @import("app.zig");

pub const Rect = struct {
    position: zlm.Vec2,
    size: zlm.Vec2,
};

pub const Anchor = enum {
    center,
    top_left,
    left_center,
};

const Text = @This();

str: []const u8,
rect: Rect,

pub fn init(str: []const u8, anchor: Anchor) Text {
    const font = &app.state.font;

    var width: f32 = 0;
    var current_width: f32 = 0;
    var height: f32 = font.line_height;

    const view = std.unicode.Utf8View.initUnchecked(str);
    var iter = view.iterator();
    while (iter.nextCodepoint()) |ch| {
        if (ch == '\n') {
            width = @max(width, current_width);
            current_width = 0;
            height += font.line_height;
            continue;
        }
        const glyph_info = font.glyphs.get(ch).?;
        current_width += glyph_info.advance;
    } else {
        width = @max(width, current_width);
    }

    const rect = switch (anchor) {
        .center => .{
            .position = zlm.vec2(-width / 2, -height / 2),
            .size = zlm.vec2(width, height),
        },
        .top_left => .{
            .position = zlm.vec2(0, -height),
            .size = zlm.vec2(width, height),
        },
        .left_center => .{
            .position = zlm.vec2(0, -height / 2),
            .size = zlm.vec2(width, height),
        },
    };

    return .{
        .str = str,
        .rect = rect,
    };
}
