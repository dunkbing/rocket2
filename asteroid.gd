extends StaticBody2D

## Set by the spawner so a destroyed asteroid can return to the pool.
var pool: Node = null

## True while this asteroid is live in the field. The spawner reads this to
## decide what to recycle / avoid overlapping — we can't use the node's
## `visible` for that anymore, since the node stays shown while its embedded
## explosion plays.
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
    if pool:
        pool.recycle(self)
    else:
        queue_free()


## Fire the asteroid's own explosion, falling back to a spawned scene if this
## variant has no embedded particle node.
func _play_explosion() -> void:
    if _explosion:
        _explosion.restart()  # one-shot burst at the asteroid's position


## Make this asteroid live again at its new position (called by the spawner).
func reset_for_spawn() -> void:
    active = true
    _sprite.show()
    _collision.set_deferred("disabled", false)


## Park this asteroid: hidden and non-collidable while it waits in the pool.
func deactivate() -> void:
    active = false
    _sprite.hide()
    _collision.set_deferred("disabled", true)
