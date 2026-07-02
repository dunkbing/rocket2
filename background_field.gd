extends Node2D

## Keeps the background star/cloud emitters centered on the target so the
## field never runs out, however far it flies. Emitted particles stay in world
## space (local_coords off), so they slide past the moving rocket instead of
## travelling along with it.

## The node to stay centered on (drag the Rocket here in the Inspector).
@export var target: Node2D


func _physics_process(_delta: float) -> void:
    if target:
        # Follow position only — never rotation — so the sky doesn't spin.
        global_position = target.global_position
