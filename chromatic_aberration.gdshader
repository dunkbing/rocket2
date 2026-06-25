shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform float strength : hint_range(0.0, 0.02, 0.0005) = 0.003;
uniform float edge_start : hint_range(0.0, 1.0) = 0.15;
uniform float edge_end : hint_range(0.0, 1.0) = 0.7;

void fragment() {
    vec2 centered_uv = SCREEN_UV - vec2(0.5);
    float distance_to_center = length(centered_uv);

    vec2 direction = normalize(centered_uv);
    float edge_amount = smoothstep(edge_start, edge_end, distance_to_center);

    vec2 offset = direction * strength * edge_amount;

    float red = texture(screen_texture, SCREEN_UV + offset).r;
    float green = texture(screen_texture, SCREEN_UV).g;
    float blue = texture(screen_texture, SCREEN_UV - offset).b;

    COLOR = vec4(red, green, blue, 1.0);
}
