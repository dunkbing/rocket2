extends Node2D

## Radius of the dark center drawn by this scene.
@export var core_radius: float = 18.0
## Slow visual spin for the outer particle ring.
@export var ring_spin_speed: float = 1.7
## Slightly faster spin for the inner particles.
@export var inner_spin_speed: float = -2.4

@export_group("Pull")
## Pull force applied to the rocket at the edge of the gravity area.
@export var pull_strength: float = 220.0
## Extra pull added near the core.
@export var pull_core_boost: float = 520.0
## Distance from the center where the pull reaches full strength.
@export var pull_core_radius: float = 24.0

@export_group("Lightning")
## Minimum seconds between lightning flashes.
@export var lightning_min_delay: float = 0.4
## Maximum seconds between lightning flashes.
@export var lightning_max_delay: float = 1.5
## How long each lightning flash stays visible.
@export var lightning_duration: float = 0.12
## Radius inside the black hole where lightning appears.
@export var lightning_radius: float = 40.0
## Number of jagged points in each lightning bolt.
@export var lightning_segments: int = 11
## Random offset applied to each lightning point.
@export var lightning_jitter: float = 8.0

var _rng := RandomNumberGenerator.new()
var _core_base_scale: Vector2 = Vector2.ONE
var _pulled_bodies: Array[RigidBody2D] = []

@onready var _core: Sprite2D = $Core
@onready var _accretion_particles: GPUParticles2D = $AccretionParticles
@onready var _inner_particles: GPUParticles2D = $InnerParticles
@onready var _lightning: Line2D = $Lightning
@onready var _lightning_timer: Timer = $LightningTimer
@onready var _pull_area: Area2D = $Area2D


func _ready() -> void:
    _rng.randomize()
    _core_base_scale = _core.scale
    _lightning.visible = false
    _pull_area.body_entered.connect(_on_pull_area_body_entered)
    _pull_area.body_exited.connect(_on_pull_area_body_exited)
    _lightning_timer.timeout.connect(_flash_lightning)
    _restart_lightning_timer()


func _process(delta: float) -> void:
    _accretion_particles.rotation += ring_spin_speed * delta
    _inner_particles.rotation += inner_spin_speed * delta


func _physics_process(_delta: float) -> void:
    for i in range(_pulled_bodies.size() - 1, -1, -1):
        var body: RigidBody2D = _pulled_bodies[i]
        if not is_instance_valid(body):
            _pulled_bodies.remove_at(i)
            continue
        var offset: Vector2 = global_position - body.global_position
        var distance: float = maxf(offset.length(), 1.0)
        var core_factor: float = 1.0 - clampf(distance / pull_core_radius, 0.0, 1.0)
        var force: float = pull_strength + pull_core_boost * core_factor
        body.apply_central_force(offset.normalized() * force)


func _restart_lightning_timer() -> void:
    _lightning_timer.start(_rng.randf_range(lightning_min_delay, lightning_max_delay))


func _flash_lightning() -> void:
    _lightning.points = _make_lightning_points()
    _lightning.visible = true

    await get_tree().create_timer(lightning_duration).timeout

    _lightning.visible = false
    _restart_lightning_timer()


func _make_lightning_points() -> PackedVector2Array:
    var count: int = maxi(lightning_segments, 2)
    var start: Vector2 = _random_inner_point()
    var end: Vector2 = _random_inner_point()
    var points := PackedVector2Array()

    for i in count:
        var t: float = float(i) / float(count - 1)
        var point: Vector2 = start.lerp(end, t)
        point += Vector2.RIGHT.rotated(_rng.randf() * TAU) * _rng.randf_range(0.0, lightning_jitter)
        points.append(point)

    return points


func _random_inner_point() -> Vector2:
    return Vector2.RIGHT.rotated(_rng.randf() * TAU) * _rng.randf_range(4.0, lightning_radius)


func _on_pull_area_body_entered(body: Node2D) -> void:
    if body is RigidBody2D and not _pulled_bodies.has(body):
        _pulled_bodies.append(body)


func _on_pull_area_body_exited(body: Node2D) -> void:
    if body is RigidBody2D:
        _pulled_bodies.erase(body)
