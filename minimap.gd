extends Control

## World distance (pixels) from the rocket that the minimap edge represents.
## Smaller = more zoomed in, so dots are spread farther apart on the map.
@export var view_radius: float = 700.0
## Blip side length in pixels (square, to match the pixel-art style).
@export var blip_size: float = 3.0
## Overall minimap opacity (0 = invisible, 1 = solid).
@export_range(0.0, 1.0, 0.05) var map_opacity: float = 0.5

@export_group("Colors")
@export var bg_color: Color = Color(0.06, 0.07, 0.10, 0.85)
@export var border_color: Color = Color(0, 0, 0, 1)
@export var rocket_color: Color = Color(1, 1, 1)
@export var asteroid_color: Color = Color(0.6, 0.62, 0.66)
@export var hazard_color: Color = Color(1, 0.35, 0.35)

## The rocket, found via the "player" group (added in rocket.gd's _ready).
var _rocket: Node2D = null


func _ready() -> void:
    modulate.a = map_opacity  # fade the whole minimap (background + blips)
    _rocket = get_tree().get_first_node_in_group("player")


func _process(_delta: float) -> void:
    queue_redraw()


func _draw() -> void:
    # Background + 1px border, drawn ourselves so it stays crisp (pixel style).
    draw_rect(Rect2(Vector2.ZERO, size), bg_color)
    draw_rect(Rect2(Vector2.ZERO, size), border_color, false, 1.0)

    var center: Vector2 = size * 0.5
    var radius: float = minf(size.x, size.y) * 0.5 - 2.0
    var scale_factor: float = radius / view_radius

    # Re-acquire the rocket if we lost it (e.g. first frame ordering).
    if _rocket == null or not is_instance_valid(_rocket):
        _rocket = get_tree().get_first_node_in_group("player")

    if _rocket:
        for a in get_tree().get_nodes_in_group("asteroids"):
            # Skip pooled asteroids that are currently parked/hidden.
            if not a.active:
                continue
            var rel: Vector2 = (a.global_position - _rocket.global_position) * scale_factor
            # Clamp to the minimap edge so far-off asteroids sit on the rim.
            if rel.length() > radius:
                rel = rel.normalized() * radius
            var col: Color = hazard_color if a.is_in_group("hazards") else asteroid_color
            _draw_blip(center + rel, col)

    # Rocket is always centered, drawn last so it sits on top of any overlap.
    _draw_blip(center, rocket_color)


func _draw_blip(pos: Vector2, color: Color) -> void:
    var top_left: Vector2 = (pos - Vector2(blip_size, blip_size) * 0.5).round()
    draw_rect(Rect2(top_left, Vector2(blip_size, blip_size)), color)
