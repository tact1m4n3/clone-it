#version 410 core

in vec2 frag_tex_coord;
flat in uint frag_blockface;

uniform sampler2D block_atlas;
uniform uint block_kind;

out vec4 color;

void main() {
    vec4 tex_color = texture(block_atlas, vec2((block_kind + frag_tex_coord.x) / 16.0, (frag_blockface + frag_tex_coord.y) / 5.0));

    color = vec4(tex_color.xyz *
        (float(frag_blockface / 2 == 0) * 0.6 + float(frag_blockface / 2 == 1) * 0.8 + float(frag_blockface / 2 == 2) * 1.0), tex_color.w);
}

