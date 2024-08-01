#version 410 core

layout(location = 0) in vec3 a_Position;
layout(location = 1) in vec3 a_Normal;

out vec3 v_Normal;
out vec4 v_Color;

struct InstanceData {
    vec4 Color;
    mat4 ModelMatrix;
};

layout(std140) uniform UniformData {
    mat4 u_ViewProjMatrix;
    InstanceData u_Instances[100];
};

void main() {
    gl_Position = u_ViewProjMatrix * u_Instances[gl_InstanceID].ModelMatrix * vec4(a_Position, 1);
    v_Normal = mat3(transpose(inverse(u_Instances[gl_InstanceID].ModelMatrix))) * a_Normal;
    v_Color = u_Instances[gl_InstanceID].Color;
}

