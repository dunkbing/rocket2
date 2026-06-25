extends Camera2D

## The node the camera should follow (drag the Rocket here in the Inspector).
@export var target: Node2D

## Peak shake strength in pixels at the start of the shake.
var _shake_strength: float = 0.0
## Seconds remaining in the current shake.
var _shake_time_left: float = 0.0
## Total duration of the current shake, used to fade the strength out.
var _shake_duration: float = 0.0


func _physics_process(delta: float) -> void:
    if target:
        # Follow position only — not rotation — so the view never spins.
        global_position = target.global_position
    # Apply shake as an offset so it doesn't fight the follow above.
    if _shake_time_left > 0.0:
        _shake_time_left -= delta
        # Fade strength from full (start) to 0 (end) over the duration.
        var amount: float = _shake_strength * (_shake_time_left / _shake_duration)
        offset = Vector2(
            randf_range(-amount, amount),
            randf_range(-amount, amount)
        )
        if _shake_time_left <= 0.0:
            offset = Vector2.ZERO


## Shake the camera at `strength` pixels for `duration` seconds.
func shake(strength: float, duration: float) -> void:
    _shake_strength = strength
    _shake_duration = maxf(duration, 0.0001)
    _shake_time_left = duration
