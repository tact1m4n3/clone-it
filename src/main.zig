const std = @import("std");
const Timer = std.time.Timer;
const gl = @import("zgl");
const zlm = @import("zlm");

const app = @import("app.zig");

pub fn main() !void {
    try app.run();
}
