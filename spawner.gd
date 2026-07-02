extends Node2D

## This node only decides WHERE asteroids appear and keeps the field populated.
## Pooling is delegated to the ObjectPool child nodes below; each pool's
## scene/size is configured on the pool node itself.

## Ring around the rocket where asteroids appear: never closer than min, never
## farther than max — so they always show up away from the rocket.
@export var spawn_min_radius: float = 260.0
@export var spawn_max_radius: float = 720.0
## How often to move asteroids that the rocket has left behind.
@export var spawn_check_interval: float = 0.25

## The rocket to spawn around / keep clear of.
@export var rocket: Node2D
## The home base; nothing may spawn on top of or overlapping it.
@export var base: Node2D
## Tries to find a non-overlapping ring spot before giving up.
@export var place_tries: int = 12

@export_group("Split")
## Hard cap on live normal asteroids so repeated splits can't flood the field.
@export var max_split_asteroids: int = 110

## The four diagonal directions a destroyed asteroid splinters into.
const _SPLIT_DIRS: Array[Vector2] = [
    Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1),
]
## Extra off-screen distance required before an asteroid can appear/reposition.
var offscreen_margin: float = 32.0

## Footprint radius for a black hole: nothing else may spawn inside this, so
## asteroids never appear already caught in the pull field (~pull area radius).
const _BLACKHOLE_RADIUS: float = 150.0
## Extra gap (px) kept between a black hole's edge and anything else.
const _BLACKHOLE_CLEARANCE: float = 40.0
## Minimum center-to-center distance between any two black holes — keeps them
## spread across the field instead of clumping.
const _BLACKHOLE_MIN_SEPARATION: float = 360.0
## Black holes are pickier to place, so give them more attempts than asteroids.
const _BLACKHOLE_PLACE_TRIES: int = 40

## Keep-clear radius around the base — covers its 206x90 footprint plus a gap.
const _BASE_CLEARANCE: float = 130.0

@onready var _pools: Array[ObjectPool] = [
    $AsteroidPool,
    $RedAsteroidPool,
    $GoldAsteroidPool,
    $BlackHolePool,
]

## Field objects currently active in the field (used by the placement algorithm).
var _active: Array[Node2D] = []
var _spawn_check_elapsed: float = 0.0


func _ready() -> void:
    add_to_group("asteroid_spawner")  # destroyed asteroids reach us via this group
    # Splits need spare capacity; the base pool is fully utilized, so let it grow.
    $AsteroidPool.allow_growth = true
    for pool in _pools:
        pool.spawned.connect(_on_asteroid_spawned)
        # When a pool despawns a dead asteroid, immediately bring one back.
        pool.despawned.connect(_on_asteroid_despawned.bind(pool))
        for i in pool.size:
            pool.spawn()


func _process(delta: float) -> void:
    if rocket == null or _active.is_empty():
        return
    _spawn_check_elapsed += delta
    if _spawn_check_elapsed < spawn_check_interval:
        return
    _spawn_check_elapsed = 0.0
    _replenish()


## A freshly spawned field object: track it and place it in the ring.
func _on_asteroid_spawned(field_object: Node2D) -> void:
    if not _active.has(field_object):
        _active.append(field_object)
    field_object.global_position = _spawn_position(field_object)


## A destroyed object was parked by its pool: drop it and spawn a fresh one.
func _on_asteroid_despawned(field_object: Node2D, pool: ObjectPool) -> void:
    _active.erase(field_object)
    pool.spawn()


## A destroyed asteroid asks to maybe split. Roll the chance stored in GameState
## and, on success, spawn four splinters around the blast point.
func try_split(origin: Vector2) -> void:
    var game_state: Node = get_tree().get_first_node_in_group("game_state")
    if game_state == null or randf() >= game_state.asteroid_split_chance:
        return
    for dir in _SPLIT_DIRS:
        if $AsteroidPool.active_count() >= max_split_asteroids:
            return  # field is full; stop splitting
        var asteroid: Node2D = $AsteroidPool.spawn()
        if asteroid == null:
            return
        # spawn() parked it on the ring; start it at the blast point and push it
        # out along its diagonal so it flies apart instead of popping into place.
        asteroid.global_position = origin
        # Stay intangible while overlapping at the center, then collide once settled.
        asteroid.set_collision_enabled(false)
        var split_offset: float = 72.0
        var target: Vector2 = origin + dir.normalized() * split_offset
        var tween: Tween = create_tween()
        var split_push_time: float = 0.35
        tween.tween_property(asteroid, "global_position", target, split_push_time) \
            .set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        tween.finished.connect(asteroid.set_collision_enabled.bind(true))


## Move one asteroid the rocket has left far behind back near it. Only an
## asteroid fully outside the viewport is eligible, so it never visibly pops.
func _replenish() -> void:
    var farthest: Node2D = null
    var farthest_distance: float = spawn_max_radius
    for asteroid in _active:
        if not _field_object_active(asteroid):
            continue
        var distance: float = asteroid.global_position.distance_to(rocket.global_position)
        var clearance: float = _field_object_radius(asteroid) + offscreen_margin
        if distance > farthest_distance and not _is_on_screen(asteroid.global_position, clearance):
            farthest = asteroid
            farthest_distance = distance
    if farthest != null:
        farthest.global_position = _spawn_position(farthest)


## A point in the ring around the rocket, outside the viewport and avoiding
## other live asteroids.
func _spawn_position(skip: Node2D) -> Vector2:
    var origin: Vector2 = rocket.global_position if rocket else global_position
    var radius: float = _field_object_radius(skip)
    var clearance: float = radius + offscreen_margin
    var tries: int = _BLACKHOLE_PLACE_TRIES if _is_blackhole(skip) else place_tries
    var best_offscreen: Vector2 = origin
    for _attempt in tries:
        var angle: float = randf() * TAU
        var distance: float = randf_range(spawn_min_radius, spawn_max_radius)
        var candidate_position: Vector2 = origin + Vector2(distance, 0.0).rotated(angle)
        if _is_on_screen(candidate_position, clearance):
            continue
        best_offscreen = candidate_position
        if not _overlaps(candidate_position, skip, radius):
            return candidate_position
    # No clear ring spot — search outward for one that's both off-screen and
    # non-overlapping; only settle for an overlapping spot if even that fails.
    var pushed: Vector2 = _offscreen_fallback(origin, skip, radius, clearance)
    if not _overlaps(pushed, skip, radius):
        return pushed
    return best_offscreen if best_offscreen != origin else pushed


## Find a guaranteed off-screen point when the configured ring is too small
## for the current viewport or every random candidate was visible.
func _offscreen_fallback(
    origin: Vector2,
    skip: Node2D,
    radius: float,
    clearance: float
) -> Vector2:
    var tries: int = _BLACKHOLE_PLACE_TRIES if _is_blackhole(skip) else place_tries
    var best: Vector2 = origin
    for _attempt in tries:
        var direction: Vector2 = Vector2.RIGHT.rotated(randf() * TAU)
        var distance: float = maxf(spawn_max_radius, spawn_min_radius)
        var candidate_position: Vector2 = origin + direction * distance
        # Push outward until the spot is off-screen AND clear of everything.
        var guard: int = 0
        while (
            _is_on_screen(candidate_position, clearance)
            or _overlaps(candidate_position, skip, radius)
        ) and guard < 24:
            distance += 64.0
            candidate_position = origin + direction * distance
            guard += 1
        best = candidate_position
        if (
            not _is_on_screen(candidate_position, clearance)
            and not _overlaps(candidate_position, skip, radius)
        ):
            return candidate_position
    return best


func _is_on_screen(world_position: Vector2, margin: float) -> bool:
    var screen_position: Vector2 = get_viewport_transform() * world_position
    return get_viewport_rect().grow(margin).has_point(screen_position)


func _field_object_active(field_object: Node2D) -> bool:
    var active: Variant = field_object.get("active")
    return active != false


func _is_blackhole(field_object: Node2D) -> bool:
    return field_object.is_in_group("blackholes")


func _field_object_radius(field_object: Node2D) -> float:
    if _is_blackhole(field_object):
        return _BLACKHOLE_RADIUS * field_object.scale.x
    var glow_radius: Variant = field_object.get("glow_radius")
    if glow_radius is float or glow_radius is int:
        return float(glow_radius) * field_object.scale.x
    return 32.0 * field_object.scale.x


func _overlaps(pos: Vector2, skip: Node2D, radius: float) -> bool:
    if base != null and pos.distance_to(base.global_position) < radius + _BASE_CLEARANCE:
        return true
    var placing_blackhole: bool = _is_blackhole(skip)
    for asteroid in _active:
        if asteroid == skip or not _field_object_active(asteroid):
            continue
        var other_radius: float = _field_object_radius(asteroid)
        var min_distance: float = radius + other_radius + 8.0
        var other_blackhole: bool = _is_blackhole(asteroid)
        # Keep extra breathing room around any black hole's pull field...
        if placing_blackhole or other_blackhole:
            min_distance = radius + other_radius + _BLACKHOLE_CLEARANCE
        # ...and force two black holes far apart, not merely non-touching.
        if placing_blackhole and other_blackhole:
            min_distance = maxf(min_distance, _BLACKHOLE_MIN_SEPARATION)
        if pos.distance_to(asteroid.global_position) < min_distance:
            return true
    return false
