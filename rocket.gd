extends RigidBody2D

@export var thrust_speed := 250.0  # upward speed while held (px/s)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
    $Fire.emitting = Input.is_action_pressed("thrust")
    if Input.is_action_pressed("thrust"):
        state.linear_velocity.y = -thrust_speed
    var target = deg_to_rad(clamp(state.linear_velocity.y * 0.1, -30.0, 90.0))
    var new_rot = lerp_angle(state.transform.get_rotation(), target, 0.1)
    state.transform = Transform2D(new_rot, state.transform.origin)
    state.angular_velocity = 0.0
