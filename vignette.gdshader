shader_type canvas_item;
render_mode unshaded;

// Base black vignette, deepened while aiming (intensity driven from rocket.gd).
uniform float radius : hint_range(0.0, 1.0) = 0.25;
uniform float softness : hint_range(0.0, 1.0) = 0.45;
uniform float intensity : hint_range(0.0, 1.0) = 0.65;

// Red edge alarm pulsed while fuel is low (alarm_intensity driven from hud.gd).
uniform float alarm_radius : hint_range(0.0, 1.0) = 0.15;
uniform float alarm_softness : hint_range(0.0, 1.0) = 0.5;
uniform float alarm_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 alarm_color : source_color = vec3(1.0, 0.0, 0.0);

void fragment() {
    vec2 centered_uv = UV - vec2(0.5);
    float distance_to_center = length(centered_uv);

    float base_alpha = smoothstep(
        radius,
        radius + softness,
        distance_to_center
    ) * intensity;
    float alarm_alpha = smoothstep(
        alarm_radius,
        alarm_radius + alarm_softness,
        distance_to_center
    ) * alarm_intensity;

    // Alpha-composite the red alarm over the black base in one pass.
    float alpha = alarm_alpha + base_alpha * (1.0 - alarm_alpha);
    vec3 color = alarm_color * alarm_alpha / max(alpha, 0.0001);
    COLOR = vec4(color, alpha);
}
