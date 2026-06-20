extends RigidBody2D

@export var thrust_speed := 250.0

var dead := false

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
    if dead:
        return
    $Fire.emitting = Input.is_action_pressed("thrust")
    if Input.is_action_pressed("thrust"):
        state.linear_velocity.y = -thrust_speed
    var target = deg_to_rad(clamp(state.linear_velocity.y * 0.1, -40.0, 90.0))
    var new_rot = lerp_angle(state.transform.get_rotation(), target, 0.1)
    state.transform = Transform2D(new_rot, state.transform.origin)
    state.angular_velocity = 0.0

func die() -> void:
    if dead:
        return
    dead = true
    freeze = true            # stop falling/moving
    $Sprite2D.hide()
    $Fire.emitting = false
    $Smoke.emitting = false
    $Explosion.emitting = true
    get_tree().call_group("hud", "on_death")
