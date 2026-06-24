shader_type canvas_item;
render_mode unshaded;

uniform float radius : hint_range(0.0, 1.0) = 0.25;
uniform float softness : hint_range(0.0, 1.0) = 0.45;
uniform float intensity : hint_range(0.0, 1.0) = 0.65;

void fragment() {
    vec2 centered_uv = UV - vec2(0.5);
    float distance_to_center = length(centered_uv);
    float vignette = smoothstep(
        radius,
        radius + softness,
        distance_to_center
    );

    COLOR = vec4(0.0, 0.0, 0.0, vignette * intensity);
}
