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
## Anything farther than this from the rocket is pulled back into the spawn
## ring, so the field always surrounds the player. Keep it a bit above
## spawn_max_radius or freshly placed objects would relocate immediately.
@export var relocate_distance: float = 820.0

## The rocket to spawn around / keep clear of.
@export var rocket: Node2D
## The home base; nothing may spawn on top of or overlapping it.
@export var base: Node2D
## Lava ground; spawned objects are kept above its top edge.
@export var ground: Node2D
## Ground-local Y position of the lava surface.
@export var ground_surface_offset_y: float = -100.0
## Tries to find a non-overlapping ring spot before giving up.
@export var place_tries: int = 20
## Minimum empty gap (px) kept between any two placed objects.
@export var min_gap: float = 32.0

@export_group("Shield")
## Seconds before a collected shield returns elsewhere in the field.
@export var shield_respawn_delay: float = 12.0

@export_group("Boss")
## UFO scene spawned once when the score reaches boss_score_threshold.
@export var boss_scene: PackedScene
## Score required to begin the boss encounter.
@export var boss_score_threshold: int = 10000
## Initial position above the rocket before the UFO settles into its hover.
@export var boss_spawn_offset: Vector2 = Vector2(0.0, -300.0)

@export_group("Split")
## Hard cap on live normal asteroids so repeated splits can't flood the field.
@export var max_split_asteroids: int = 110

@export_group("Meteor")
## Random wait (seconds) between meteor drops.
@export var meteor_interval_min: float = 6.0
@export var meteor_interval_max: float = 14.0
## How far above the rocket a meteor starts falling.
@export var meteor_spawn_height: float = 1200.0
## Horizontal scatter around the rocket for the drop point.
@export var meteor_spread_x: float = 240.0
## A meteor this far below the rocket is gone for good — free it.
@export var meteor_cull_distance: float = 900.0

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
## Meteors are pooled but NOT part of _pools: they're dropped on a timer, not
## placed in the ring around the rocket.
@onready var _meteor_pool: ObjectPool = $MeteorPool
## Shields use the same ring placement, but respawn on a pickup timer.
@onready var _shield_pool: ObjectPool = $ShieldPool

## Field objects currently active in the field (used by the placement algorithm).
var _active: Array[Node2D] = []
var _spawn_check_elapsed: float = 0.0

## Live falling meteors (not pooled; freed once far below the rocket).
var _meteors: Array[RigidBody2D] = []
var _meteor_elapsed: float = 0.0
var _meteor_wait: float = 0.0
var _boss_spawned: bool = false


func _ready() -> void:
    add_to_group("asteroid_spawner")  # destroyed asteroids reach us via this group
    # Splits need spare capacity; the base pool is fully utilized, so let it grow.
    $AsteroidPool.allow_growth = true
    for pool in _pools:
        pool.spawned.connect(_on_asteroid_spawned)
        # When a pool despawns a dead asteroid, immediately bring one back.
        pool.despawned.connect(_on_asteroid_despawned.bind(pool))
    _shield_pool.spawned.connect(_on_asteroid_spawned)
    # Let the camera apply its first transform before checking what is off-screen.
    await get_tree().physics_frame
    for pool in _pools:
        for i in pool.size:
            pool.spawn()
    for i in _shield_pool.size:
        _shield_pool.spawn()
    _meteor_wait = randf_range(meteor_interval_min, meteor_interval_max)


func _process(delta: float) -> void:
    if rocket == null:
        return
    _boss_tick()
    _meteor_tick(delta)
    if _active.is_empty():
        return
    _spawn_check_elapsed += delta
    if _spawn_check_elapsed < spawn_check_interval:
        return
    _spawn_check_elapsed = 0.0
    _replenish()


func _boss_tick() -> void:
    if _boss_spawned or boss_scene == null:
        return
    var game_state: Node = get_tree().get_first_node_in_group("game_state")
    if game_state == null or int(game_state.get("score")) < boss_score_threshold:
        return
    _boss_spawned = true
    var boss: Node2D = boss_scene.instantiate()
    boss.set("rocket", rocket)
    get_tree().current_scene.add_child(boss)
    boss.global_position = _clamp_above_ground(
        rocket.global_position + boss_spawn_offset,
        64.0
    )


## Count toward the next random meteor drop. The timer only runs while the
## rocket is actually flying (freeze is true in the menu and while aiming), so
## meteors never rain on the menu screen or a parked rocket.
func _meteor_tick(delta: float) -> void:
    if _meteor_pool == null:
        return
    _cull_meteors()
    if rocket.get("freeze") != false:
        return
    _meteor_elapsed += delta
    if _meteor_elapsed < _meteor_wait:
        return
    _meteor_elapsed = 0.0
    _meteor_wait = randf_range(meteor_interval_min, meteor_interval_max)
    _drop_meteor()


## Shoot one meteor from a random point far above the rocket, aimed straight
## at the rocket's current position.
func _drop_meteor() -> void:
    var meteor: RigidBody2D = _meteor_pool.spawn()
    if meteor == null:
        return  # every pooled meteor is mid-air; skip this drop
    meteor.global_position = _clamp_above_ground(
        rocket.global_position + Vector2(
            randf_range(-meteor_spread_x, meteor_spread_x),
            -meteor_spawn_height
        ),
        32.0
    )
    var aim: Vector2 = (rocket.global_position - meteor.global_position).normalized()
    ## Downward launch speed range (gravity accelerates it further).
    var meteor_speed_min = 100.0
    var meteor_speed_max = 200.0
    meteor.linear_velocity = aim * randf_range(meteor_speed_min, meteor_speed_max)
    _meteors.append(meteor)


## Park meteors that have fallen far below the rocket — they can never return.
func _cull_meteors() -> void:
    for i in range(_meteors.size() - 1, -1, -1):
        var meteor: RigidBody2D = _meteors[i]
        # Exploded meteors are parked (out of tree) by the pool via `died`.
        if not is_instance_valid(meteor) or not meteor.is_inside_tree():
            _meteors.remove_at(i)
        elif meteor.global_position.y > rocket.global_position.y + meteor_cull_distance:
            _meteors.remove_at(i)
            _meteor_pool.despawn(meteor)


## A freshly spawned field object: track it and place it in the ring.
func _on_asteroid_spawned(field_object: Node2D) -> void:
    if not _active.has(field_object):
        _active.append(field_object)
    field_object.global_position = _spawn_position(field_object)


## A destroyed object was parked by its pool: drop it and spawn a fresh one.
func _on_asteroid_despawned(field_object: Node2D, pool: ObjectPool) -> void:
    _active.erase(field_object)
    pool.spawn()


## Rocket pickup entry point. Defer removal because this starts in a body contact.
func collect_shield(shield: Node2D) -> void:
    call_deferred("_collect_shield", shield)


func _collect_shield(shield: Node2D) -> void:
    if not _active.has(shield):
        return
    _active.erase(shield)
    _shield_pool.despawn(shield)
    await get_tree().create_timer(shield_respawn_delay).timeout
    if is_instance_valid(_shield_pool):
        _shield_pool.spawn()


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
        var asteroid_radius: float = _field_object_radius(asteroid)
        asteroid.global_position = _clamp_above_ground(origin, asteroid_radius)
        # Stay intangible while overlapping at the center, then collide once settled.
        asteroid.set_collision_enabled(false)
        var split_offset: float = 72.0
        var target: Vector2 = _clamp_above_ground(
            origin + dir.normalized() * split_offset,
            asteroid_radius
        )
        var tween: Tween = create_tween()
        var split_push_time: float = 0.35
        tween.tween_property(asteroid, "global_position", target, split_push_time) \
            .set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        tween.finished.connect(asteroid.set_collision_enabled.bind(true))


## Hard cap on relocations per check: bounds the per-frame placement cost so a
## big trailing band of asteroids is pulled in over a few ticks, not one frame.
const _MAX_RELOCATIONS_PER_CHECK: int = 6


## Keep the field wrapped around the rocket: every object the rocket has left
## farther than relocate_distance behind is moved back into the spawn ring.
## Only objects fully outside the viewport are touched, so nothing visibly pops.
func _replenish() -> void:
    var relocated: int = 0
    for asteroid in _active:
        if not _field_object_active(asteroid):
            continue
        var distance: float = asteroid.global_position.distance_to(rocket.global_position)
        if distance <= relocate_distance:
            continue
        var clearance: float = _field_object_radius(asteroid) + offscreen_margin
        if _is_on_screen(asteroid.global_position, clearance):
            continue
        asteroid.global_position = _spawn_position(asteroid)
        relocated += 1
        if relocated >= _MAX_RELOCATIONS_PER_CHECK:
            return


## A point in the ring around the rocket, outside the viewport and avoiding
## other live asteroids.
func _spawn_position(skip: Node2D) -> Vector2:
    var origin: Vector2 = rocket.global_position if rocket else global_position
    var radius: float = _field_object_radius(skip)
    var clearance: float = radius + offscreen_margin
    var tries: int = _BLACKHOLE_PLACE_TRIES if _is_blackhole(skip) else place_tries
    for _attempt in tries:
        var angle: float = randf() * TAU
        var distance: float = randf_range(spawn_min_radius, spawn_max_radius)
        var candidate_position: Vector2 = origin + Vector2(distance, 0.0).rotated(angle)
        if not _is_above_ground(candidate_position, radius):
            continue
        if _is_on_screen(candidate_position, clearance):
            continue
        if not _overlaps(candidate_position, skip, radius):
            return candidate_position
    return _offscreen_fallback(origin, skip, radius, clearance)


## Find a guaranteed off-screen point when the configured ring is too small
## for the current viewport or every random candidate was visible.
func _offscreen_fallback(
    origin: Vector2,
    skip: Node2D,
    radius: float,
    clearance: float
) -> Vector2:
    var tries: int = _BLACKHOLE_PLACE_TRIES if _is_blackhole(skip) else place_tries
    for _attempt in tries:
        # Search upward so extending the fallback can never dive into the lava.
        var direction: Vector2 = Vector2.RIGHT.rotated(randf_range(PI, TAU))
        var distance: float = maxf(spawn_max_radius, spawn_min_radius)
        var candidate_position: Vector2 = origin + direction * distance
        # Push outward until the spot is off-screen AND clear of everything.
        var guard: int = 0
        while not _valid_spawn_position(
            candidate_position,
            skip,
            radius,
            clearance
        ) and guard < 24:
            distance += 64.0
            candidate_position = origin + direction * distance
            guard += 1
        if _valid_spawn_position(candidate_position, skip, radius, clearance):
            return candidate_position

    # Crowded field: scan increasingly large upper semicircles. Unlike the old
    # fallback, this never returns a known-overlapping or below-lava position.
    var slots: int = 12
    for ring in 24:
        var scan_distance: float = maxf(spawn_max_radius, spawn_min_radius) + ring * 128.0
        for slot in slots:
            var scan_angle: float = PI + (float(slot) + 0.5) * PI / float(slots)
            var scan_position: Vector2 = (
                origin + Vector2.RIGHT.rotated(scan_angle) * scan_distance
            )
            if _valid_spawn_position(scan_position, skip, radius, clearance):
                return scan_position

    # Extreme fallback: walk upward until a verified clear point is found.
    var emergency_position: Vector2 = (
        origin + Vector2(0.0, -spawn_max_radius - 4096.0)
    )
    while not _valid_spawn_position(emergency_position, skip, radius, clearance):
        emergency_position.y -= 512.0
    return emergency_position


func _valid_spawn_position(
    pos: Vector2,
    skip: Node2D,
    radius: float,
    clearance: float
) -> bool:
    return (
        _is_above_ground(pos, radius)
        and not _is_on_screen(pos, clearance)
        and not _overlaps(pos, skip, radius)
    )


## Keep an object's full footprint plus the normal placement gap above lava.
func _clamp_above_ground(pos: Vector2, radius: float) -> Vector2:
    if ground == null:
        return pos
    var surface_y: float = ground.global_position.y + ground_surface_offset_y
    pos.y = minf(pos.y, surface_y - radius - min_gap)
    return pos


func _is_above_ground(pos: Vector2, radius: float) -> bool:
    if ground == null:
        return true
    var surface_y: float = ground.global_position.y + ground_surface_offset_y
    return pos.y + radius + min_gap <= surface_y


## Distance from `pos` to the closest other live field object (or the base).
func _nearest_neighbor_distance(pos: Vector2, skip: Node2D) -> float:
    var nearest: float = INF
    if base != null:
        nearest = pos.distance_to(base.global_position)
    for other in _active:
        if other == skip or not _field_object_active(other):
            continue
        nearest = minf(nearest, pos.distance_to(other.global_position))
    return nearest


func _is_on_screen(world_position: Vector2, margin: float) -> bool:
    var screen_position: Vector2 = get_viewport_transform() * world_position
    return get_viewport_rect().grow(margin).has_point(screen_position)


func _field_object_active(field_object: Node2D) -> bool:
    if field_object.is_in_group("shields"):
        return field_object.is_inside_tree()
    var active: Variant = field_object.get("active")
    return active != false


func _is_blackhole(field_object: Node2D) -> bool:
    return field_object.is_in_group("blackholes")


func _field_object_radius(field_object: Node2D) -> float:
    if _is_blackhole(field_object):
        return _BLACKHOLE_RADIUS * field_object.scale.x
    if field_object.is_in_group("shields"):
        return 32.0 * field_object.scale.x
    var glow_radius: Variant = field_object.get("glow_radius")
    if glow_radius is float or glow_radius is int:
        return float(glow_radius) * field_object.scale.x
    return 32.0 * field_object.scale.x


func _overlaps(pos: Vector2, skip: Node2D, radius: float) -> bool:
    if rocket != null:
        var rocket_clearance: float = maxf(spawn_min_radius, radius + offscreen_margin)
        if pos.distance_to(rocket.global_position) < rocket_clearance:
            return true
    if base != null and pos.distance_to(base.global_position) < radius + _BASE_CLEARANCE:
        return true
    var placing_blackhole: bool = _is_blackhole(skip)
    for asteroid in _active:
        if asteroid == skip or not _field_object_active(asteroid):
            continue
        var other_radius: float = _field_object_radius(asteroid)
        var min_distance: float = radius + other_radius + min_gap
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
