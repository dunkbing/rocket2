extends StaticBody2D

## Emitted when the death sequence finishes. The ObjectPool listens for this and
## despawns us automatically — so we need no back-reference to the pool/spawner.
signal died

## How long to linger after exploding (so the embedded explosion particles can
## finish) before reporting that we're done and ready to be recycled.
@export var death_duration: float = 1.2

## True while live in the field. The spawner reads this for its placement logic.
var active: bool = false

@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _sprite: Sprite2D = $Sprite2D
## The asteroid's own explosion particles (may be absent on some variants).
@onready var _explosion: GPUParticles2D = get_node_or_null("Explosion")


func _ready() -> void:
    # The rocket looks for this group to know what it can destroy.
    add_to_group("asteroids")


## Called by the rocket when it hits this asteroid.
func explode() -> void:
    if not active:
        return
    active = false
    # Defer: we're inside a physics collision callback, so we can't change the
    # scene tree right now.
    _do_explode.call_deferred()


func _do_explode() -> void:
    # Hide the rock but keep the node around so its particles can finish.
    _sprite.hide()
    _collision.set_deferred("disabled", true)
    _play_explosion()
    get_tree().call_group("hud", "on_asteroid_destroyed")
    # Linger so the explosion plays out, then let the pool recycle us.
    await get_tree().create_timer(death_duration).timeout
    died.emit()


## Fire the asteroid's own explosion (variants without one simply skip it).
func _play_explosion() -> void:
    if _explosion:
        _explosion.restart()  # one-shot burst at the asteroid's position


## ObjectPool hook: bring this asteroid to life (the spawner positions it after).
func on_spawned() -> void:
    active = true
    _sprite.show()
    _collision.set_deferred("disabled", false)


## ObjectPool hook: park this asteroid (hidden, non-collidable) for reuse.
func on_despawned() -> void:
    active = false
    _sprite.hide()
    _collision.set_deferred("disabled", true)
