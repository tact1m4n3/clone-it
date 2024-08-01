#version 410 core

in vec3 v_Normal;
in vec4 v_Color;

out vec4 f_Color;

void main() {
    vec3 lightDir = vec3(1, 1, -1);
    vec3 lightColor = vec3(1, 1, 1);
    float ambient = 0.4;

    float diffuse = max(dot(normalize(v_Normal), normalize(lightDir)), 0);
    f_Color = vec4((ambient + diffuse) * v_Color.rgb, v_Color.w);
}
