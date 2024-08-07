#version 410 core

#define M_TAU 2.0 * 3.14159265358979323846264338327950288419716939937510

layout(location = 0) in vec3 position;

// TODO: Use UBOs
uniform float screen_aspect_ratio;
uniform float world_scale;
uniform float world_yaw;

vec3 rotateYaw(vec3 v) {
    float yaw = world_yaw - 3.0 / 8.0 * M_TAU;

    return vec3(
        v.x * cos(yaw) + v.y * sin(yaw),
        v.y * cos(yaw) - v.x * sin(yaw),
        v.z
    );
}

vec3 project(vec3 v) {
    // TODO: Figure out z
    return vec3(sqrt(3.0) * 0.5 * (v.y - v.x) / screen_aspect_ratio, v.z - 0.5 * (v.x + v.y), -length(v) / 1000.0) * pow(2, world_scale);
}

void main() {
    gl_Position = vec4(project(rotateYaw(position)), 1.0);
}
