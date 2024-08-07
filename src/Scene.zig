const Event = @import("app.zig").Event;

const Scene = @This();

ptr: *anyopaque,
impl: *const Interface,

pub const Interface = struct {
    on_event: *const fn (*anyopaque, event: Event) void,
    update: *const fn (*anyopaque, f32) void,
    render: *const fn (*anyopaque) void,
};

pub fn from(comptime T: type, scene: *anyopaque) Scene {
    const self: *T = @ptrCast(@alignCast(scene));
    return Scene{
        .ptr = self,
        .impl = &.{
            .on_event = T.on_event,
            .update = T.update,
            .render = T.render,
        },
    };
}

pub fn on_event(self: Scene, event: Event) void {
    self.impl.on_event(self.ptr, event);
}

pub fn update(self: Scene, dt: f32) void {
    self.impl.update(self.ptr, dt);
}

pub fn render(self: Scene) void {
    self.impl.render(self.ptr);
}
