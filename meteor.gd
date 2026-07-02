extends RigidBody2D

## Emitted when the death sequence finishes. The MeteorPool listens for this
## and despawns us automatically.
signal died

## How long to linger after exploding (so the explosion particles can finish)
## before reporting that we're done and ready to be recycled.
@export var death_duration: float = 1.2

## True while falling. The spawner and the rocket ignore parked meteors.
var active: bool = false

@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _explosion: GPUParticles2D = $Explosion
@onready var _trail: GPUParticles2D = $Particles


## Called by the rocket on impact.
func explode() -> void:
    if not active:
        return
    active = false
    # Defer: we're inside a physics collision callback.
    _do_explode.call_deferred()


func _do_explode() -> void:
    # Hide the rock but keep the node around so its particles can finish.
    _sprite.hide()
    _trail.emitting = false
    _collision.set_deferred("disabled", true)
    freeze = true  # stop falling so the explosion stays at the impact point
    _explosion.restart()
    await get_tree().create_timer(death_duration).timeout
    died.emit()


## ObjectPool hook: reset for a new drop (the spawner positions/launches us).
func on_spawned() -> void:
    active = true
    freeze = false
    _sprite.show()
    _collision.set_deferred("disabled", false)
    _trail.restart()  # clear the previous fall's leftover trail
    _trail.emitting = true


## ObjectPool hook: park (hidden, inert) for reuse.
func on_despawned() -> void:
    active = false
    _sprite.hide()
    _collision.set_deferred("disabled", true)
