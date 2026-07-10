extends CharacterBody2D

signal defeated

## Rocket this boss follows and shoots at. The spawner assigns it at runtime.
@export var rocket: Node2D

@export_group("Health")
## Hits required to defeat the boss.
@export var max_health: int = 10
## Brief immunity after a hit prevents one impact from registering twice.
@export var hit_cooldown: float = 0.3

@export_group("Movement")
## How quickly the UFO moves toward its hovering position.
@export var move_speed: float = 120.0
## Vertical distance the UFO tries to keep above the rocket.
@export var hover_height: float = 170.0
## Width and speed of its side-to-side movement.
@export var hover_width: float = 80.0
@export var hover_speed: float = 1.4

@export_group("Attack")
## Seconds between attack patterns.
@export var shoot_interval: float = 1.25
## Bullet travel speed in pixels per second.
@export var bullet_speed: float = 250.0
## Seconds before a missed bullet returns to the pool.
@export var bullet_lifetime: float = 5.0
## Total angle covered by the three-bullet aimed fan.
@export_range(5.0, 90.0, 1.0) var fan_angle_degrees: float = 28.0
## Time the predictive shot warns the player before it launches.
@export var predictive_delay: float = 0.45
## How far ahead along the rocket's velocity the predictive shot aims.
@export var predictive_lead_time: float = 0.6
## Number of evenly spaced positions used by the radial burst.
@export_range(6, 24, 1) var ring_bullet_count: int = 14
## Width of the safe opening in the radial burst.
@export_range(15.0, 120.0, 1.0) var ring_gap_degrees: float = 55.0

@onready var _bullet_pool: ObjectPool = $BulletPool
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _impact: GPUParticles2D = $Impact
@onready var _explosion: GPUParticles2D = $Explosion

var _health: int
var _hit_cooldown_left: float = 0.0
var _hover_elapsed: float = 0.0
var _shoot_elapsed: float = 0.0
var _attack_pattern: int = 0
var _dead: bool = false
var _active_bullets: Array[Area2D] = []


func _ready() -> void:
    add_to_group("bosses")
    _health = max_health
    if rocket == null:
        rocket = get_tree().get_first_node_in_group("player") as Node2D
    _health_bar.max_value = max_health
    _health_bar.value = _health


func _physics_process(delta: float) -> void:
    if _dead:
        return
    _hit_cooldown_left = maxf(_hit_cooldown_left - delta, 0.0)
    _update_bullets(delta)
    if not is_instance_valid(rocket):
        rocket = get_tree().get_first_node_in_group("player") as Node2D
        return
    _move(delta)
    _attack(delta)


## Returns true when this impact removed health.
func take_damage(amount: int = 1) -> bool:
    if _dead or _hit_cooldown_left > 0.0:
        return false
    _hit_cooldown_left = hit_cooldown
    _impact.restart()
    _health = maxi(_health - amount, 0)
    _health_bar.value = _health
    if _health <= 0:
        _defeat()
    return true


func _move(delta: float) -> void:
    _hover_elapsed += delta
    var desired_position: Vector2 = rocket.global_position + Vector2(
        sin(_hover_elapsed * hover_speed) * hover_width,
        -hover_height
    )
    var offset: Vector2 = desired_position - global_position
    velocity = offset.limit_length(move_speed)
    move_and_slide()


func _attack(delta: float) -> void:
    if rocket.get("freeze") != false or not rocket.visible:
        _shoot_elapsed = 0.0
        return
    _shoot_elapsed += delta
    if _shoot_elapsed < shoot_interval:
        return
    _shoot_elapsed = 0.0
    _shoot()


func _shoot() -> void:
    match _attack_pattern:
        0:
            _shoot_aimed_fan()
        1:
            _shoot_predictive()
        2:
            _shoot_gap_ring()
    _attack_pattern = (_attack_pattern + 1) % 3


func _shoot_aimed_fan() -> void:
    var aim_angle: float = (rocket.global_position - global_position).angle()
    var half_angle: float = deg_to_rad(fan_angle_degrees) * 0.5
    var offsets: Array[float] = [-half_angle, 0.0, half_angle]
    for offset in offsets:
        _spawn_bullet(Vector2.RIGHT.rotated(aim_angle + offset))


func _shoot_predictive() -> void:
    var rocket_velocity: Vector2 = Vector2.ZERO
    if rocket is RigidBody2D:
        rocket_velocity = (rocket as RigidBody2D).linear_velocity
    var prediction_time: float = predictive_delay + predictive_lead_time
    var target_position: Vector2 = rocket.global_position + rocket_velocity * prediction_time
    var direction: Vector2 = (target_position - global_position).normalized()
    _spawn_bullet(direction, predictive_delay)


func _shoot_gap_ring() -> void:
    var gap_angle: float = (rocket.global_position - global_position).angle()
    var gap_half_angle: float = deg_to_rad(ring_gap_degrees) * 0.5
    for i in ring_bullet_count:
        var angle: float = TAU * float(i) / float(ring_bullet_count)
        var angle_from_gap: float = absf(wrapf(angle - gap_angle, -PI, PI))
        if angle_from_gap <= gap_half_angle:
            continue
        _spawn_bullet(Vector2.RIGHT.rotated(angle))


func _spawn_bullet(direction: Vector2, launch_delay: float = 0.0) -> void:
    var bullet: Area2D = _bullet_pool.spawn() as Area2D
    if bullet == null:
        return
    if not bullet.has_meta("ufo_connected"):
        bullet.body_entered.connect(_on_bullet_body_entered.bind(bullet))
        bullet.set_meta("ufo_connected", true)
    bullet.top_level = true
    bullet.global_position = global_position + direction * 38.0
    bullet.rotation = direction.angle()
    bullet.modulate = Color.WHITE
    bullet.scale = Vector2.ONE
    bullet.monitoring = launch_delay <= 0.0
    bullet.set_meta("velocity", Vector2.ZERO if launch_delay > 0.0 else direction * bullet_speed)
    bullet.set_meta("launch_velocity", direction * bullet_speed)
    bullet.set_meta("launch_delay", launch_delay)
    bullet.set_meta("age", 0.0)
    bullet.set_meta("active", true)
    _active_bullets.append(bullet)
    _set_bullet_trail(bullet, launch_delay <= 0.0)


func _update_bullets(delta: float) -> void:
    for i in range(_active_bullets.size() - 1, -1, -1):
        var bullet: Area2D = _active_bullets[i]
        if not is_instance_valid(bullet) or not bullet.is_inside_tree():
            _active_bullets.remove_at(i)
            continue
        var age: float = float(bullet.get_meta("age", 0.0)) + delta
        bullet.set_meta("age", age)
        var launch_delay: float = float(bullet.get_meta("launch_delay", 0.0))
        if launch_delay > 0.0:
            launch_delay = maxf(launch_delay - delta, 0.0)
            bullet.set_meta("launch_delay", launch_delay)
            var pulse: float = 0.85 + sin(age * 28.0) * 0.15
            bullet.modulate = Color(1.0, pulse * 0.5, pulse * 0.5, 1.0)
            bullet.scale = Vector2.ONE * (1.0 + (1.0 - pulse) * 0.5)
            if launch_delay <= 0.0:
                bullet.modulate = Color.WHITE
                bullet.scale = Vector2.ONE
                bullet.set_meta("velocity", bullet.get_meta("launch_velocity", Vector2.ZERO))
                bullet.set_deferred("monitoring", true)
                _set_bullet_trail(bullet, true)
        var bullet_velocity: Vector2 = bullet.get_meta("velocity", Vector2.ZERO)
        bullet.global_position += bullet_velocity * delta
        if age >= bullet_lifetime:
            _despawn_bullet(bullet)


func _on_bullet_body_entered(body: Node, bullet: Area2D) -> void:
    if not bullet.get_meta("active", false):
        return
    bullet.set_meta("active", false)
    if body.is_in_group("player") and body.has_method("kill"):
        var blocked: bool = (
            body.has_method("is_shielded")
            and bool(body.call("is_shielded"))
        )
        if not blocked:
            body.kill()
    call_deferred("_despawn_bullet", bullet)


func _despawn_bullet(bullet: Area2D) -> void:
    if not is_instance_valid(bullet) or not _active_bullets.has(bullet):
        return
    _active_bullets.erase(bullet)
    bullet.set_meta("active", false)
    bullet.modulate = Color.WHITE
    bullet.scale = Vector2.ONE
    bullet.monitoring = false
    _set_bullet_trail(bullet, false)
    _bullet_pool.despawn(bullet)


func _set_bullet_trail(bullet: Area2D, on: bool) -> void:
    var trail: GPUParticles2D = bullet.get_node_or_null("Trail") as GPUParticles2D
    if trail == null:
        return
    trail.restart()
    trail.emitting = on


func _defeat() -> void:
    _dead = true
    velocity = Vector2.ZERO
    $Sprite2D.hide()
    _health_bar.hide()
    _impact.emitting = false
    _explosion.restart()
    call_deferred("_clear_bullets")
    defeated.emit()
    set_deferred("collision_layer", 0)
    set_deferred("collision_mask", 0)
    get_tree().create_timer(_explosion.lifetime).timeout.connect(queue_free)


func _clear_bullets() -> void:
    while not _active_bullets.is_empty():
        _despawn_bullet(_active_bullets.back())
