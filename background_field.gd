extends Node2D

## Keeps the background star/cloud emitters centered on the target so the
## field never runs out, however far it flies. Emitted particles stay in world
## space (local_coords off), so they slide past the moving rocket instead of
## travelling along with it.

## The node to stay centered on (drag the Rocket here in the Inspector).
@export var target: Node2D
## Ground used to keep sky particles above its surface.
@export var ground: Node2D
## Vertical half-size of the particle emission boxes in main.tscn.
@export var emission_half_height: float = 750.0
## Extra empty sky gap above the lava surface.
@export var ground_clearance: float = 150.0


func _physics_process(_delta: float) -> void:
    if target:
        # Follow position only — never rotation — so the sky doesn't spin.
        var field_position: Vector2 = target.global_position
        if ground:
            var sky_bottom: float = ground.global_position.y - ground_clearance
            field_position.y = minf(field_position.y, sky_bottom - emission_half_height)
        global_position = field_position
