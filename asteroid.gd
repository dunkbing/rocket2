extends StaticBody2D

## Emitted when the death sequence finishes. The ObjectPool listens for this and
## despawns us automatically — so we need no back-reference to the pool/spawner.
signal died

## How long to linger after exploding (so the embedded explosion particles can
## finish) before reporting that we're done and ready to be recycled.
@export var death_duration: float = 1.2

## Floating text scene shown on destruction (assign floating_text.tscn).
@export var floating_text_scene: PackedScene
## Score awarded when destroyed (shown as "+score").
@export var score: int = 1
## Coins awarded when destroyed (shown as "+coin$"; 0 hides the coin line).
@export var coin: int = 0

## True while live in the field. The spawner reads this for its placement logic.
var active: bool = false

@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _sprite: Sprite2D = $Sprite2D
## The asteroid's own explosion particles (may be absent on some variants).
@onready var _explosion: GPUParticles2D = $Explosion
## Pop-in animation played on spawn (may be absent on some variants).
@onready var _anim: AnimationPlayer = $AnimationPlayer


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
    _show_floating_text()
    get_tree().call_group("game_state", "add_stats", score, coin)
    # Chance-based split into four (rolled & spawned by the asteroid spawner).
    get_tree().call_group("asteroid_spawner", "try_split", global_position)
    # Linger so the explosion plays out, then let the pool recycle us.
    await get_tree().create_timer(death_duration).timeout
    died.emit()


## Fire the asteroid's own explosion (variants without one simply skip it).
func _play_explosion() -> void:
    if _explosion:
        _explosion.restart()  # one-shot burst at the asteroid's position


## Spawn the floating score text into the scene so it outlives this asteroid.
## The scene's AnimationPlayer handles the rise/fade and frees it.
func _show_floating_text() -> void:
    if floating_text_scene == null:
        return
    var popup: Node = floating_text_scene.instantiate()
    if popup.has_method("setup"):
        popup.setup(score, coin)
    get_tree().current_scene.add_child(popup)
    popup.global_position = global_position


## Enable/disable collision (used while split splinters fly out from the blast).
func set_collision_enabled(on: bool) -> void:
    _collision.set_deferred("disabled", not on)


## ObjectPool hook: bring this asteroid to life (the spawner positions it after).
func on_spawned() -> void:
    active = true
    _sprite.show()
    _collision.set_deferred("disabled", false)
    if _anim and _anim.has_animation("spawn"):
        _anim.play("spawn")
        _anim.seek(0.0, true)  # apply the zero-scale frame now: no full-size flash


## ObjectPool hook: park this asteroid (hidden, non-collidable) for reuse.
func on_despawned() -> void:
    active = false
    _sprite.hide()
    _collision.set_deferred("disabled", true)
    if _anim:
        _anim.stop()
