extends Node2D

const ASTEROID := preload("res://asteroid.tscn")
const POOL_SIZE := 60          # max asteroids alive at once; columns skip if exhausted
const SPEED := 100.0           # left scroll speed (match the rocket's world feel)
const SPAWN_INTERVAL := 0.5    # spawn small clusters often for a continuous cloud
const SPAWN_X := 300.0         # just off the right edge (viewport is 288 wide)
const X_SPREAD := 120.0        # random horizontal scatter so they don't line up
const SCREEN_H := 512.0
const CLUSTER := 5             # asteroids dropped per tick
const GAP_HEIGHT := 130.0      # clear lane the rocket flies through (always kept empty)
const GAP_DRIFT := 40.0        # lane wander per tick; < scroll-per-tick so the path stays followable
const BASE_RADIUS := 16.0      # asteroid bounding radius at scale 1 (from the capsule)
const SCALE_MIN := 0.6
const SCALE_MAX := 1.5
const PLACE_TRIES := 8         # attempts to find a non-overlapping spot before giving up

var pool: Array = []
var gap_y := SCREEN_H * 0.5    # center of the clear lane, random-walks over time

func _ready() -> void:
    for i in POOL_SIZE:
        var a = ASTEROID.instantiate()
        _deactivate(a)
        a.body_entered.connect(_on_hit)
        add_child(a)
        pool.append(a)

    var t := Timer.new()
    t.wait_time = SPAWN_INTERVAL
    t.timeout.connect(_spawn_cluster)
    add_child(t)
    t.start()

func _process(delta: float) -> void:
    for a in pool:
        if not a.visible:
            continue
        a.position.x -= SPEED * delta
        if a.position.x < -40.0:
            _deactivate(a)

func _spawn_cluster() -> void:
    # keep gap_y far enough from edges that BOTH bands always have room for an asteroid
    var margin := GAP_HEIGHT * 0.5 + 55.0
    gap_y = clamp(gap_y + randf_range(-GAP_DRIFT, GAP_DRIFT), margin, SCREEN_H - margin)
    for i in CLUSTER:
        _try_place(i % 2 == 0)  # alternate above / below so neither side is ever empty

func _try_place(above: bool) -> void:
    for attempt in PLACE_TRIES:
        var s := randf_range(SCALE_MIN, SCALE_MAX)  # re-rolled per try so a smaller one can fit a thin band
        var r := BASE_RADIUS * s
        var lo: float
        var hi: float
        if above:
            lo = r
            hi = gap_y - GAP_HEIGHT * 0.5 - r
        else:
            lo = gap_y + GAP_HEIGHT * 0.5 + r
            hi = SCREEN_H - r
        if hi <= lo:
            continue  # too big for this band, re-roll a smaller one
        var x := SPAWN_X + randf_range(0.0, X_SPREAD)
        var y := randf_range(lo, hi)
        if _overlaps(x, y, r):
            continue  # would touch another asteroid -> try another spot
        _activate(x, y, s)
        return
    # ponytail: no free spot in PLACE_TRIES, just drop this one -> self-limits density

func _overlaps(x: float, y: float, r: float) -> bool:
    for a in pool:
        if not a.visible:
            continue
        if Vector2(x, y).distance_to(a.position) < r + BASE_RADIUS * a.scale.x:
            return true
    return false

func _activate(x: float, y: float, s: float) -> void:
    var a = _get_free()
    if a == null:
        return  # ponytail: pool exhausted, skip; bump POOL_SIZE if the field looks sparse
    a.position = Vector2(x, y)
    a.scale = Vector2(s, s)
    a.rotation = randf_range(0.0, TAU)
    a.show()
    a.set_deferred("monitoring", true)

func _deactivate(a) -> void:
    a.hide()
    a.set_deferred("monitoring", false)
    a.position.x = -1000.0  # park off-screen so _process skips it

func _get_free():
    for a in pool:
        if not a.visible:
            return a
    return null

func _on_hit(_body: Node) -> void:
    get_tree().reload_current_scene()  # ponytail: game over = reset; swap for real UI later
