#version 410 core

in vec4 a_Position;
in vec4 a_Color;
in vec2 a_TexCoord;

out vec4 v_Color;
out vec2 v_TexCoord;

uniform mat4 u_ViewProjMatrix;

void main() {
    gl_Position = u_ViewProjMatrix * a_Position;
    v_Color = a_Color;
    v_TexCoord = a_TexCoord;
}

