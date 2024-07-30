const zlm = @import("zlm");

const Transform = @This();

// we can also use custom math here, dropping zlm

position: zlm.Vec3 = zlm.Vec3.zero,
rotation: zlm.Vec3 = zlm.Vec3.zero, // we can use quaternions once we have them
scale: zlm.Vec3 = zlm.Vec3.one,

pub fn lerp(a: Transform, b: Transform, t: f32) Transform {
    return .{
        .position = a.position.lerp(b.position, t),
        .rotation = a.rotation.lerp(b.rotation, t),
        .scale = a.scale.lerp(b.scale, t),
    };
}

pub fn compute_matrix(self: Transform) zlm.Mat4 {
    return zlm.Mat4.createScale(self.scale.x, self.scale.y, self.scale.z)
        .mul(zlm.Mat4.createAngleAxis(zlm.vec3(1, 0, 0), self.rotation.x))
        .mul(zlm.Mat4.createAngleAxis(zlm.vec3(0, 1, 0), self.rotation.y))
        .mul(zlm.Mat4.createAngleAxis(zlm.vec3(0, 0, 0), self.rotation.z))
        .mul(zlm.Mat4.createTranslationXYZ(self.position.x, self.position.y, self.position.z));
}
