extends Area2D

## A small homing missile the main rocket randomly shoots out while flying.
## It curves toward the nearest asteroid with a side-to-side weave (so the path
## reads as a swooping arc, not a straight line), pops asteroids on contact, and
## frees itself after `lifetime`.

## Flight speed (pixels/second).
@export var speed: float = 320.0
## Steering responsiveness toward the target (higher = turns tighter).
@export var turn_rate: float = 5.0
## Amplitude (radians) of the weave layered onto the aim for a curvy path.
@export var wander_strength: float = 0.7
## Weave frequency.
@export var wander_freq: float = 7.0
## Seconds before it fizzles out and frees itself.
@export var lifetime: float = 3.0
## How often to re-pick the nearest asteroid.
@export var retarget_interval: float = 0.25

var _vel: Vector2 = Vector2.RIGHT
var _time: float = 0.0
var _retarget_elapsed: float = 0.0
var _target: Node2D


func _ready() -> void:
    body_entered.connect(_on_body_entered)
    _target = _nearest_asteroid()


## Aim it in an initial heading (the firing rocket's direction). Call after spawn.
func launch(direction: Vector2) -> void:
    if direction.length() > 0.01:
        _vel = direction.normalized() * speed
        rotation = _vel.angle()


func _physics_process(delta: float) -> void:
    _time += delta
    _retarget_elapsed += delta
    if _retarget_elapsed >= retarget_interval or not _is_valid(_target):
        _retarget_elapsed = 0.0
        _target = _nearest_asteroid()

    var heading: float = _vel.angle()
    if _is_valid(_target):
        # Weave around the straight line to the target so the arc looks nicer.
        var aim: float = (_target.global_position - global_position).angle()
        aim += sin(_time * wander_freq) * wander_strength
        heading = lerp_angle(heading, aim, clampf(turn_rate * delta, 0.0, 1.0))
    else:
        heading += sin(_time * wander_freq) * wander_strength * delta

    _vel = Vector2.RIGHT.rotated(heading) * speed
    global_position += _vel * delta
    rotation = heading

    if _time >= lifetime:
        queue_free()


func _on_body_entered(body: Node) -> void:
    if body.is_in_group("asteroids") and body.has_method("explode"):
        body.explode()  # the asteroid awards score/coins itself


## Closest live asteroid, or null if the field is empty.
func _nearest_asteroid() -> Node2D:
    var nearest: Node2D = null
    var best: float = INF
    for a in get_tree().get_nodes_in_group("asteroids"):
        if not (a is Node2D) or not _is_valid(a):
            continue
        var d: float = global_position.distance_squared_to(a.global_position)
        if d < best:
            best = d
            nearest = a
    return nearest


## Valid = still in the tree and not a parked (destroyed) pool asteroid.
func _is_valid(a: Node2D) -> bool:
    return is_instance_valid(a) and a.get("active") != false
