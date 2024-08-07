#version 410 core

in vec2 v_TexCoord;

out vec4 f_Color;

uniform float u_Transparency;
uniform sampler2DMS u_Texture;

void main() {
    vec2 textureSize = textureSize(u_Texture);
    vec4 color = texelFetch(u_Texture, ivec2(textureSize * v_TexCoord), 0)
            + texelFetch(u_Texture, ivec2(textureSize * v_TexCoord), 1)
            + texelFetch(u_Texture, ivec2(textureSize * v_TexCoord), 2)
            + texelFetch(u_Texture, ivec2(textureSize * v_TexCoord), 3);
    color /= 4;
    color.w = u_Transparency;
    f_Color = color;
}
