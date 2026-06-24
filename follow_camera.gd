extends Camera2D

## The node the camera should follow (drag the Rocket here in the Inspector).
@export var target: Node2D


func _physics_process(_delta: float) -> void:
    if target:
        # Follow position only — not rotation — so the view never spins.
        global_position = target.global_position
