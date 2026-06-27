shader_type canvas_item;
render_mode unshaded;

// Red edge vignette used as a low-fuel alarm. `intensity` is driven from
// hud.gd (0 = invisible, pulses up while fuel is low).
uniform float radius : hint_range(0.0, 1.0) = 0.15;
uniform float softness : hint_range(0.0, 1.0) = 0.5;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 vignette_color : source_color = vec3(1.0, 0.0, 0.0);

void fragment() {
    vec2 centered_uv = UV - vec2(0.5);
    float distance_to_center = length(centered_uv);
    float vignette = smoothstep(
        radius,
        radius + softness,
        distance_to_center
    );

    COLOR = vec4(vignette_color, vignette * intensity);
}
