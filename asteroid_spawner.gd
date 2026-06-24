extends Node2D

## The asteroid scene to pool.
@export var asteroid_scene: PackedScene
## How many asteroids live in the pool (also the max alive at once).
@export var pool_size: int = 24
## Random size range applied to each asteroid when (re)spawned.
@export var min_scale: float = 0.8
@export var max_scale: float = 2.0
## Asteroids (re)spawn in a ring around the rocket: never closer than min,
## never farther than max — so they always appear away from the rocket.
@export var spawn_min_radius: float = 260.0
@export var spawn_max_radius: float = 720.0
## How often to move asteroids that the rocket has left behind.
@export var spawn_check_interval: float = 0.25
## Extra distance outside the viewport required before an asteroid can appear
## or be recycled. This prevents popping at the edge of the screen.
@export var offscreen_margin: float = 32.0
## Seconds before a destroyed asteroid respawns somewhere else.
@export var respawn_delay: float = 1.2
## The rocket to spawn around / keep clear of.
@export var rocket: Node2D
## Tries to find a ring spot not overlapping another asteroid before giving up.
@export var place_tries: int = 12

var _pool: Array[Node2D] = []
var _spawn_check_elapsed: float = 0.0


func _ready() -> void:
    if asteroid_scene == null:
        push_warning("AsteroidSpawner: no asteroid_scene assigned.")
        return
    for i in pool_size:
        var asteroid: Node2D = asteroid_scene.instantiate()
        asteroid.pool = self
        add_child(asteroid)
        _pool.append(asteroid)
        _activate(asteroid)


func _process(delta: float) -> void:
    if rocket == null or _pool.is_empty():
        return
    _spawn_check_elapsed += delta
    if _spawn_check_elapsed < spawn_check_interval:
        return
    _spawn_check_elapsed = 0.0
    _replenish_asteroids()


## Hand a destroyed asteroid back to the pool; it reappears later elsewhere.
func recycle(asteroid: Node2D) -> void:
    asteroid.deactivate()
    await get_tree().create_timer(respawn_delay).timeout
    if is_instance_valid(asteroid) and is_inside_tree():
        _activate(asteroid)


## Move one asteroid left outside the spawn ring back near the rocket. Only an
## asteroid fully outside the viewport is eligible, so it never visibly pops.
func _replenish_asteroids() -> void:
    var farthest: Node2D = null
    var farthest_distance: float = spawn_max_radius
    for asteroid in _pool:
        if not asteroid.visible:
            continue
        var distance: float = asteroid.global_position.distance_to(rocket.global_position)
        var clearance: float = _asteroid_radius(asteroid) + offscreen_margin
        if distance > farthest_distance and not _is_on_screen(asteroid.global_position, clearance):
            farthest = asteroid
            farthest_distance = distance
    if farthest != null:
        _activate(farthest)


func _activate(asteroid: Node2D) -> void:
    asteroid.rotation = randf() * TAU
    asteroid.scale = Vector2.ONE * randf_range(min_scale, max_scale)
    asteroid.global_position = _spawn_position(asteroid)
    asteroid.reset_for_spawn()


## A point in the ring around the rocket, outside the viewport and avoiding
## other live asteroids.
func _spawn_position(skip: Node2D) -> Vector2:
    var origin: Vector2 = rocket.global_position if rocket else global_position
    var radius: float = _asteroid_radius(skip)
    var clearance: float = radius + offscreen_margin
    var best_offscreen: Vector2 = origin
    for _attempt in place_tries:
        var angle: float = randf() * TAU
        var distance: float = randf_range(spawn_min_radius, spawn_max_radius)
        var candidate_position: Vector2 = origin + Vector2(distance, 0.0).rotated(angle)
        if _is_on_screen(candidate_position, clearance):
            continue
        best_offscreen = candidate_position
        if not _overlaps(candidate_position, skip, radius):
            return candidate_position
    if best_offscreen != origin:
        return best_offscreen
    return _offscreen_fallback(origin, skip, radius, clearance)


## Find a guaranteed off-screen point when the configured ring is too small
## for the current viewport or every random candidate was visible.
func _offscreen_fallback(
    origin: Vector2,
    skip: Node2D,
    radius: float,
    clearance: float
) -> Vector2:
    var best: Vector2 = origin
    for _attempt in place_tries:
        var direction: Vector2 = Vector2.RIGHT.rotated(randf() * TAU)
        var distance: float = maxf(spawn_max_radius, spawn_min_radius)
        var candidate_position: Vector2 = origin + direction * distance
        while _is_on_screen(candidate_position, clearance):
            distance += 64.0
            candidate_position = origin + direction * distance
        best = candidate_position
        if not _overlaps(candidate_position, skip, radius):
            return candidate_position
    return best


func _is_on_screen(world_position: Vector2, margin: float) -> bool:
    var screen_position: Vector2 = get_viewport_transform() * world_position
    return get_viewport_rect().grow(margin).has_point(screen_position)


func _asteroid_radius(asteroid: Node2D) -> float:
    return 32.0 * asteroid.scale.x


func _overlaps(pos: Vector2, skip: Node2D, radius: float) -> bool:
    for asteroid in _pool:
        if asteroid == skip or not asteroid.visible:
            continue
        var other_radius: float = _asteroid_radius(asteroid)
        if pos.distance_to(asteroid.global_position) < radius + other_radius + 8.0:
            return true
    return false
