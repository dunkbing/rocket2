extends RigidBody2D

## How hard the rocket launches. The drag distance (in pixels) is multiplied
## by this to get the launch speed.
@export var power: float = 8.0
## Cap on launch speed so a huge drag doesn't fling it off-screen.
@export var max_launch_speed: float = 750.0
## How many dots to draw in the trajectory preview (keep it small = short line).
@export var trajectory_points: int = 8
## Seconds between each simulated trajectory dot.
@export var trajectory_step: float = 0.05
## Radius of the dot nearest the rocket.
@export var dot_start_radius: float = 4.0
## Radius of the farthest dot (dots shrink from start to end).
@export var dot_end_radius: float = 1.0

@export_group("Aim Effects")
@export_range(0.05, 1.0, 0.05) var aim_time_scale: float = 0.25
@export_range(0.0, 1.0, 0.05) var idle_vignette: float = 0.65
@export_range(0.0, 1.0, 0.05) var aim_vignette: float = 0.9
@export var aim_effect_duration: float = 0.7
@export var vignette: ColorRect
@export var camera: Camera2D
@export_range(0.5, 2.0, 0.05) var normal_camera_zoom: float = 1.0
@export_range(0.5, 2.0, 0.05) var aim_camera_zoom: float = 1.2

@export_group("Impact")
## Speed the rocket keeps after smashing an asteroid so it punches through and
## keeps flying instead of stopping dead. If it was already faster, it keeps its
## own speed; this is just the floor.
@export var punch_through_speed: float = 400.0
## How much the post-hit direction is pulled toward straight-up (0 = keep
## heading, 1 = always straight up). The rocket keeps its horizontal lean but
## never gets blasted downward.
@export_range(0.0, 1.0, 0.05) var punch_upward_bias: float = 0.55

var _aiming: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _launched: bool = false
## Trajectory dot positions in the rocket's local space.
var _dots: PackedVector2Array = PackedVector2Array()
## Color of the trajectory dots.
var dot_color: Color = Color(1, 1, 1, 0.8)

var _aim_effect_tween: Tween
var _camera_tween: Tween

## Velocity to re-apply on the next physics frame so a hit doesn't stop us.
var _punch_velocity: Vector2 = Vector2.ZERO
var _punch_pending: bool = false


func _ready() -> void:
    # Rocket sits still until launched.
    freeze = true
    _set_exhaust(false)
    _clear_trajectory()
    # Report contacts so we can blow up asteroids we hit.
    contact_monitor = true
    max_contacts_reported = 4
    body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
    # Asteroids add themselves to the "asteroids" group in their _ready().
    if body.is_in_group("asteroids") and body.has_method("explode"):
        # Capture our travel direction NOW, before the collision solver can slow
        # us. We re-apply it in _integrate_forces so the rocket punches through.
        if _launched:
            var direction: Vector2 = linear_velocity
            if direction.length() < 1.0:
                direction = Vector2.RIGHT.rotated(rotation)
            direction = direction.normalized()
            # First make sure we're never pointing down, then blend toward
            # straight-up so even a fast horizontal hit reliably pops upward
            # while keeping its left/right lean.
            direction.y = -absf(direction.y)
            direction = direction.lerp(Vector2.UP, punch_upward_bias)
            var speed: float = maxf(linear_velocity.length(), punch_through_speed)
            _punch_velocity = direction.normalized() * speed
            _punch_pending = true
        body.explode()


func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            # Start a drag from anywhere on screen — the launch direction comes
            # from the drag, not from where you press, so it always works.
            _start_aim()
        elif _aiming:
            _aiming = false
            _launch()

    elif event is InputEventMouseMotion and _aiming:
        var velocity: Vector2 = _launch_velocity()
        _update_trajectory(velocity)
        # Point the rocket where it's about to shoot while you aim.
        if velocity.length() > 0.0:
            rotation = velocity.angle()


## Begin a new aim, stopping the rocket wherever it currently is.
func _start_aim() -> void:
    _aiming = true
    _launched = false
    _drag_start = get_global_mouse_position()
    # Halt any current motion and hold the rocket still while aiming.
    freeze = true
    linear_velocity = Vector2.ZERO
    angular_velocity = 0.0
    _set_exhaust(false)
    _set_aim_effect(true)


## Velocity the rocket will get if launched right now.
## Drag BEHIND the rocket -> it shoots the OPPOSITE way (slingshot feel).
func _launch_velocity() -> Vector2:
    var drag: Vector2 = _drag_start - get_global_mouse_position()
    var velocity: Vector2 = drag * power
    if velocity.length() > max_launch_speed:
        velocity = velocity.normalized() * max_launch_speed
    return velocity


func _launch() -> void:
    _set_aim_effect(false)
    var velocity: Vector2 = _launch_velocity()
    _clear_trajectory()
    if velocity.length() <= 0.0:
        return  # tapped without dragging — stay put
    _launched = true
    freeze = false
    linear_velocity = velocity
    _set_exhaust(true)


# While flying, keep the nose pointed along the current velocity so the rocket
# follows its arc instead of staying at a fixed angle.
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
    if not _launched:
        return
    # Runs AFTER collision resolution, so this overrides the velocity the solver
    # zeroed out when we rammed the (static) asteroid.
    if _punch_pending:
        state.linear_velocity = _punch_velocity
        _punch_pending = false
    var velocity: Vector2 = state.linear_velocity
    if velocity.length() > 1.0:
        var xform := state.transform
        xform = Transform2D(velocity.angle(), xform.origin)
        state.transform = xform
        state.angular_velocity = 0.0


## Turn the exhaust (fire + smoke) trail on or off.
func _set_exhaust(on: bool) -> void:
    $Fire.emitting = on
    $Smoke.emitting = on


## Simulate where the rocket will travel and store dots along that arc.
func _update_trajectory(velocity: Vector2) -> void:
    _dots.clear()
    var gravity: Vector2 = (
        ProjectSettings.get_setting("physics/2d/default_gravity_vector")
        * ProjectSettings.get_setting("physics/2d/default_gravity")
        * gravity_scale
    )
    var pos: Vector2 = global_position  # simulate in world space (gravity is world-space)
    var vel: Vector2 = velocity
    for i in trajectory_points:
        # Convert each world-space point into the rocket's (rotated) local
        # space so _draw() places the dots along the true flight arc.
        _dots.append(to_local(pos))
        vel += gravity * trajectory_step
        pos += vel * trajectory_step
    queue_redraw()


func _clear_trajectory() -> void:
    _dots.clear()
    queue_redraw()


# Draw the trajectory as dots that shrink with distance from the rocket.
func _draw() -> void:
    var count: int = _dots.size()
    for i in count:
        var t: float = float(i) / float(maxi(count - 1, 1))
        var radius: float = lerpf(dot_start_radius, dot_end_radius, t)
        draw_circle(_dots[i], radius, dot_color)


func _set_aim_effect(active: bool) -> void:
    Engine.time_scale = aim_time_scale if active else 1.0
    _set_camera_focus(active)

    if vignette == null:
        return

    var shader_material := vignette.material as ShaderMaterial
    if shader_material == null:
        return

    if _aim_effect_tween != null and _aim_effect_tween.is_valid():
        _aim_effect_tween.kill()

    var current: float = float(
        shader_material.get_shader_parameter("intensity")
    )
    var target: float = aim_vignette if active else idle_vignette

    _aim_effect_tween = create_tween()
    _aim_effect_tween.set_ignore_time_scale(true)
    _aim_effect_tween.set_trans(Tween.TRANS_SINE)
    _aim_effect_tween.set_ease(Tween.EASE_IN_OUT)
    _aim_effect_tween.tween_method(
        _set_vignette_intensity,
        current,
        target,
        aim_effect_duration
    )


func _set_vignette_intensity(value: float) -> void:
    if vignette == null:
        return

    var shader_material := vignette.material as ShaderMaterial
    if shader_material:
        shader_material.set_shader_parameter("intensity", value)


func _exit_tree() -> void:
    Engine.time_scale = 1.0
    
func _set_camera_focus(active: bool) -> void:
    if camera == null:
        return

    if _camera_tween != null and _camera_tween.is_valid():
        _camera_tween.kill()

    var zoom_amount: float = (
        aim_camera_zoom if active else normal_camera_zoom
    )

    _camera_tween = create_tween()
    _camera_tween.set_ignore_time_scale(true)
    _camera_tween.set_trans(Tween.TRANS_SINE)
    _camera_tween.set_ease(Tween.EASE_IN_OUT)
    _camera_tween.tween_property(
        camera,
        "zoom",
        Vector2.ONE * zoom_amount,
        aim_effect_duration
    )
