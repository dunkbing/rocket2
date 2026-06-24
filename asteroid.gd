extends StaticBody2D

## Particle explosion spawned when this asteroid is destroyed.
@export var explosion_scene: PackedScene

## Set by the spawner so a destroyed asteroid can return to the pool.
var pool: Node = null

var _exploded: bool = false
@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
    # The rocket looks for this group to know what it can destroy.
    add_to_group("asteroids")


## Called by the rocket when it hits this asteroid.
func explode() -> void:
    if _exploded:
        return
    _exploded = true
    # Defer: we're inside a physics collision callback, so we can't change the
    # scene tree right now.
    _do_explode.call_deferred()


func _do_explode() -> void:
    if explosion_scene:
        var fx: Node2D = explosion_scene.instantiate()
        fx.global_position = global_position
        # Add to the scene root so the effect outlives this asteroid.
        get_tree().current_scene.add_child(fx)
    get_tree().call_group("hud", "on_asteroid_destroyed")
    if pool:
        pool.recycle(self)
    else:
        queue_free()


## Make this asteroid live again at its new position (called by the spawner).
func reset_for_spawn() -> void:
    _exploded = false
    show()
    _collision.set_deferred("disabled", false)


## Park this asteroid: hidden and non-collidable while it waits in the pool.
func deactivate() -> void:
    hide()
    _collision.set_deferred("disabled", true)
