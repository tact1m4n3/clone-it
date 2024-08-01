#version 410 core

layout(location = 0) in vec3 a_Position;
layout(location = 1) in vec3 a_Normal;

out vec3 v_Normal;

uniform mat4 u_ViewProjMatrix;
uniform mat4 u_ModelMatrix;

void main() {
    gl_Position = u_ViewProjMatrix * u_ModelMatrix * vec4(a_Position, 1);
    v_Normal = mat3(transpose(inverse(u_ModelMatrix))) * a_Normal;
}

