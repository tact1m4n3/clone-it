#version 410 core

in vec3 v_Normal;

out vec4 f_Color;

void main() {
    vec3 color = vec3(0.2, 0.5, 0.6);

    vec3 lightDir = vec3(1, 0.5, 1);
    vec3 lightColor = vec3(1, 1, 1);
    float ambient = 0.4;

    float diffuse = max(dot(normalize(v_Normal), normalize(lightDir)), 0);
    f_Color = vec4((ambient + diffuse) * color, 1);
}
