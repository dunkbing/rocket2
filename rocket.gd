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
## Below 1.0 = zoom OUT while aiming (wider view to see where you're shooting).
@export_range(0.5, 2.0, 0.05) var aim_camera_zoom: float = 0.8

@export_group("Charge (aim timer)")
## How long (real seconds) you may hold a drag before time runs out. If the
## charge bar empties before you release, the rocket dies and explodes.
@export var aim_time_limit: float = 1.2
## Explosion spawned when the rocket dies. Assign explosion.tscn in the editor.
@export var death_explosion_scene: PackedScene
## Seconds to let the death explosion play before the Game Over popup appears.
@export var death_popup_delay: float = 0.8
## Camera shake strength (pixels) when the rocket dies.
@export var death_shake_strength: float = 16.0
## How long the death camera shake lasts (seconds).
@export var death_shake_duration: float = 0.4
## Charge FX scale at the start of a drag (just began charging).
@export var charge_fx_min_scale: float = 0.5
## Charge FX scale once the charge is nearly full (held the longest).
@export var charge_fx_max_scale: float = 1.5

@export_group("Fuel")
## Maximum fuel. The fuel bar shows the current amount as a fraction of this.
@export var max_fuel: float = 100.0
## Fuel burned per second while the rocket is flying.
@export var fuel_drain_rate: float = 14.0
## Fuel restored each time the rocket destroys an asteroid.
@export var fuel_refill: float = 35.0

@export_group("Impact")
## Speed the rocket keeps after smashing an asteroid so it punches through and
## keeps flying instead of stopping dead. If it was already faster, it keeps its
## own speed; this is just the floor.
@export var punch_through_speed: float = 400.0
## How much the post-hit direction is pulled toward straight-up (0 = keep
## heading, 1 = always straight up). The rocket keeps its horizontal lean but
## never gets blasted downward.
@export_range(0.0, 1.0, 0.05) var punch_upward_bias: float = 0.55
## Soft haptic buzz length (ms) on the phone when smashing an asteroid. 0 = off.
var hit_haptic_ms: int = 20

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

## Real seconds left in the current aim before the rocket times out and dies.
var _aim_time_left: float = 0.0
## Current fuel; drains in flight, refills on hits. Drag is blocked at 0.
var _fuel: float = 0.0
## Set once the rocket has timed out — ignores all further input.
var _dead: bool = false


func _ready() -> void:
    # Rocket sits still until launched.
    add_to_group("player")  # the minimap finds us via this group
    freeze = true
    _set_exhaust(false)
    _set_charge_fx(false)
    _clear_trajectory()
    # Report contacts so we can blow up asteroids we hit.
    contact_monitor = true
    max_contacts_reported = 4
    body_entered.connect(_on_body_entered)
    _fuel = max_fuel
    _push_fuel()
    _push_charge(1.0)  # full when idle; only drains while dragging


func _process(delta: float) -> void:
    if _dead:
        return
    if _aiming:
        # Count down in REAL time so the aim slow-mo doesn't stretch the timer.
        var real_delta: float = delta / maxf(Engine.time_scale, 0.0001)
        _aim_time_left -= real_delta
        var charge: float = clampf(_aim_time_left / aim_time_limit, 0.0, 1.0)
        _push_charge(charge)
        # Grow the charge FX the longer you hold (charge counts down 1 -> 0).
        $Charge.scale = Vector2.ONE * lerpf(charge_fx_min_scale, charge_fx_max_scale, 1.0 - charge)
        if _aim_time_left <= 0.0:
            _die()
    elif _launched and not freeze:
        # Burn fuel while coasting through space.
        _fuel = maxf(_fuel - fuel_drain_rate * delta, 0.0)
        _push_fuel()


func _on_body_entered(body: Node) -> void:
    # Deadly red asteroids kill on contact — check this first, since they're
    # also in the "asteroids" group via the shared script.
    if body.is_in_group("hazards"):
        _die()
        return
    # Asteroids add themselves to the "asteroids" group in their _ready().
    if body.is_in_group("asteroids") and body.has_method("explode"):
        # Smashing an asteroid tops the fuel back up.
        _fuel = minf(_fuel + fuel_refill, max_fuel)
        _push_fuel()
        $HitSound.play()   # impact thud
        # Soft buzz: short, low amplitude. No-op on desktop.
        Input.vibrate_handheld(hit_haptic_ms, 0.4)
        # Gold asteroids reward a coin ding on top of the normal hit.
        if body.is_in_group("gold"):
            $CoinSound.play()
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


func _unhandled_input(event: InputEvent) -> void:
    if _dead:
        return
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
    # Out of fuel: the player can't drag/launch anymore.
    if _fuel <= 0.0:
        return
    get_tree().call_group("hud", "enter_game_mode")
    _aiming = true
    _launched = false
    _aim_time_left = aim_time_limit
    _push_charge(1.0)
    _drag_start = get_global_mouse_position()
    # Halt any current motion and hold the rocket still while aiming.
    freeze = true
    linear_velocity = Vector2.ZERO
    angular_velocity = 0.0
    _set_exhaust(false)
    _set_charge_fx(true)
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
    _set_charge_fx(false)
    _push_charge(1.0)  # released in time — reset the aim-timer bar to full
    var velocity: Vector2 = _launch_velocity()
    _clear_trajectory()
    if velocity.length() <= 0.0:
        return  # tapped without dragging — stay put
    _launched = true
    freeze = false
    linear_velocity = velocity
    _set_exhaust(true)
    _play_launch_puff()
    $ShootSound.play()


# While flying, keep the nose pointed along the current velocity so the rocket
# follows its arc instead of staying at a fixed angle.
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
    if _dead:
        # Hard stop: zero velocity every frame so gravity can't keep pulling the
        # corpse down (freeze set during a collision callback isn't reliable).
        state.linear_velocity = Vector2.ZERO
        state.angular_velocity = 0.0
        return
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


## Turn the charge-up particles on or off (shown while aiming/charging).
## Boost speed_scale by the inverse of the aim slow-mo so the swirl keeps
## running at real-time speed instead of crawling along with everything else.
func _set_charge_fx(on: bool) -> void:
    $Charge.speed_scale = (1.0 / maxf(aim_time_scale, 0.0001)) if on else 1.0
    $Charge.emitting = on
    # Reset to the starting size each time charging begins/ends.
    $Charge.scale = Vector2.ONE * charge_fx_min_scale


## One-shot puff burst fired the instant the rocket launches. Slow-mo is already
## off by launch, so no speed_scale boost is needed.
func _play_launch_puff() -> void:
    $Charge/Puff.visible = true
    $Charge/Puff.speed_scale = 1.0
    $Charge/Puff.restart()


## Aim timed out while still dragging — blow the rocket up and end the run.
func _die() -> void:
    if _dead:
        return
    _dead = true
    _aiming = false
    _launched = false
    _set_aim_effect(false)
    _set_exhaust(false)
    _set_charge_fx(false)
    _clear_trajectory()
    _push_charge(0.0)
    $DeathSound.play()
    if death_explosion_scene:
        var fx: Node2D = death_explosion_scene.instantiate()
        fx.global_position = global_position
        get_tree().current_scene.add_child(fx)
    if camera and camera.has_method("shake"):
        camera.shake(death_shake_strength, death_shake_duration)
    # Deferred: _die() may run inside a physics collision callback, where
    # changing physics state directly is ignored.
    set_deferred("freeze", true)
    set_deferred("linear_velocity", Vector2.ZERO)
    hide()
    # Let the explosion play out, then show the Game Over popup.
    await get_tree().create_timer(death_popup_delay).timeout
    get_tree().call_group("hud", "on_rocket_dead")


## Push the current aim-timer fill (0..1) to the HUD.
func _push_charge(ratio: float) -> void:
    get_tree().call_group("hud", "set_charge", ratio)


## Push the current fuel fill (0..1) to the HUD.
func _push_fuel() -> void:
    get_tree().call_group("hud", "set_fuel", _fuel / max_fuel)


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


# Draw the trajectory as pixel squares that shrink with distance from the
# rocket. We snap to whole pixels and use draw_rect (no anti-aliasing) so the
# markers read as crisp blocks instead of smooth circles.
func _draw() -> void:
    var count: int = _dots.size()
    for i in count:
        var t: float = float(i) / float(maxi(count - 1, 1))
        # dot_*_radius is treated as half the square's side here.
        var side: float = maxf(roundf(lerpf(dot_start_radius, dot_end_radius, t) * 2.0), 1.0)
        var top_left: Vector2 = _dots[i].round() - Vector2(side, side) * 0.5
        draw_rect(Rect2(top_left, Vector2(side, side)), dot_color)


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
