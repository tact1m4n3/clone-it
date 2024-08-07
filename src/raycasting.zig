const std = @import("std");
const zlm = @import("zlm");

pub const Bbox = struct {
    min: zlm.Vec3,
    max: zlm.Vec3,

    pub fn transform(self: Bbox, matrix: zlm.Mat4) Bbox {
        return .{
            .min = zlm.vec4(self.min.x, self.min.y, self.min.z, 1.0).transform(matrix).swizzle("xyz"),
            .max = zlm.vec4(self.max.x, self.max.y, self.max.z, 1.0).transform(matrix).swizzle("xyz"),
        };
    }
};

pub const Ray = struct {
    orig: zlm.Vec3,
    dir: zlm.Vec3,

    pub fn transform(self: Ray, matrix: zlm.Mat4) Bbox {
        return .{
            .orig = zlm.vec4(self.orig.x, self.orig.y, self.orig.z, 1.0).transform(matrix).swizzle("xyz"),
            .max = zlm.vec4(self.orig.x, self.orig.y, self.orig.z, 1.0).transform(matrix).swizzle("xyz"),
        };
    }

    pub fn intersects(self: Ray, bbox: Bbox) bool {
        var tmin = (bbox.min.x - self.orig.x) / self.dir.x;
        var tmax = (bbox.max.x - self.orig.x) / self.dir.x;

        if (tmin > tmax) std.mem.swap(f32, &tmin, &tmax);

        var tymin = (bbox.min.y - self.orig.y) / self.dir.y;
        var tymax = (bbox.max.y - self.orig.y) / self.dir.y;

        if (tymin > tymax) std.mem.swap(f32, &tymin, &tymax);

        if (tmin > tymax or tymin > tmax)
            return false;

        if (tymin > tmin) tmin = tymin;
        if (tymax < tmax) tmax = tymax;

        var tzmin = (bbox.min.z - self.orig.z) / self.dir.z;
        var tzmax = (bbox.max.z - self.orig.z) / self.dir.z;

        if (tzmin > tzmax) std.mem.swap(f32, &tzmin, &tzmax);

        return !(tmin > tzmax or tzmin > tmax);
    }
};
