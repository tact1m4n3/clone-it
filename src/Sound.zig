const std = @import("std");
const Allocator = std.mem.Allocator;
const zaudio = @import("zaudio");

pub const Options = struct {
    volume: f32 = 1,
    loop: bool = false,
};

const Sound = @This();

inner: *zaudio.Sound,

pub fn init(engine: *zaudio.Engine, comptime name: [:0]const u8, options: Options) !Sound {
    const inner = try engine.createSoundFromFile("assets/sounds/" ++ name, .{ .flags = .{ .stream = true } });
    inner.setVolume(options.volume);
    inner.setLooping(options.loop);

    return .{
        .inner = inner,
    };
}

pub fn deinit(self: *Sound) void {
    self.inner.destroy();
}

pub fn play(self: *Sound) void {
    const log = std.log.scoped(.sound);

    if (self.inner.isPlaying()) return;
    self.inner.start() catch log.warn("Failed to play sound...", .{});
}
