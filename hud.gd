extends CanvasLayer

## Full-screen red vignette (lives on the PostFX layer) pulsed when fuel is low.
@export var low_fuel_overlay: ColorRect

## Fuel fraction at/below which the low-fuel warning kicks in.
const LOW_FUEL_RATIO := 0.25
## Peak alpha of the red screen vignette at the top of each pulse.
const LOW_FUEL_INTENSITY := 0.2

@onready var GameUI: Control = $GameUI
@onready var LowFuelLabel: Label = $GameUI/LowFuelLabel
@onready var ScoreLabel: Label = $GameUI/ScoreLabel
@onready var CoinLabel: Label = $GameUI/CoinLabel
@onready var PauseButton = $GameUI/PauseButton
@onready var ResumeButton = $PauseMenu/Panel/VBoxContainer/ResumeButton
@onready var RestartButton = $PauseMenu/Panel/VBoxContainer/RestartButton
@onready var ChargeBar: ProgressBar = $GameUI/ChargeBar
@onready var FuelBar: ProgressBar = $GameUI/FuelBar
@onready var DeathRestartButton = $DeathPanel/Panel/VBoxContainer/RestartButton
@onready var DeathScoreLabel = $DeathPanel/Panel/VBoxContainer/ScoreLabel
@onready var MenuUI: Control = $MenuUI
@onready var MenuHighScoreLabel: Label = $MenuUI/MenuStats/HighScoreLabel
@onready var MenuCoinLabel: Label = $MenuUI/MenuStats/CoinLabel
@onready var PlayTabButton: Button = $MenuUI/BottomTabs/MarginContainer/HBoxContainer/PlayButton
@onready var UpgradeTabButton: Button = $MenuUI/BottomTabs/MarginContainer/HBoxContainer/UpgradeButton
@onready var ShopTabButton: Button = $MenuUI/BottomTabs/MarginContainer/HBoxContainer/ShopButton
@onready var SettingsButton: Button = $MenuUI/SettingsButton
@onready var SettingsPanel: Control = $MenuUI/SettingsPanel
@onready var SoundCheck: CheckBox = $MenuUI/SettingsPanel/Panel/VBoxContainer/SoundCheck
@onready var MusicCheck: CheckBox = $MenuUI/SettingsPanel/Panel/VBoxContainer/MusicCheck
@onready var SettingsCloseButton: Button = $MenuUI/SettingsPanel/Panel/VBoxContainer/CloseButton

## Latest values pushed from GameState; cached for the game-over panel.
var _score := 0
var _coin := 0

## True while the low-fuel warning is active; the looping pulse tween.
var _low_fuel := false
var _low_fuel_tween: Tween


func _ready() -> void:
    add_to_group("hud")  # the game state & rocket reach us via this group
    PauseButton.pressed.connect(_pause)
    ResumeButton.pressed.connect(_resume)
    RestartButton.pressed.connect(_restart)
    DeathRestartButton.pressed.connect(_restart)
    PlayTabButton.pressed.connect(_play_from_tabs)
    UpgradeTabButton.pressed.connect(_select_upgrade_tab)
    ShopTabButton.pressed.connect(_select_shop_tab)
    SettingsButton.pressed.connect(_open_settings)
    SettingsCloseButton.pressed.connect(_close_settings)
    ScoreLabel.text = str(_score)
    CoinLabel.text = "%d$" % _coin
    # Sensible defaults in case the rocket's first emit beat us into the tree.
    ChargeBar.value = 1.0
    FuelBar.value = 1.0
    _select_bottom_tab("play")
    # Sync the checkboxes to the current bus state BEFORE wiring `toggled`, so
    # the initial assignment doesn't re-trigger the handlers.
    SoundCheck.button_pressed = not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX"))
    MusicCheck.button_pressed = not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music"))
    SoundCheck.toggled.connect(_on_sound_toggled)
    MusicCheck.toggled.connect(_on_music_toggled)
    GameUI.hide()  # menu is up at first; the in-game HUD stays hidden until Play

# --- Stat display (called via the "hud" group from GameState) ---

## Show the session score.
func set_score(value: int) -> void:
    _score = value
    ScoreLabel.text = str(value)

## Show the session coin count.
func set_coin(value: int) -> void:
    _coin = value
    CoinLabel.text = "%d$" % value

## Best score ever — shown in the top-left menu stats (not during a run).
func set_high_score(value: int) -> void:
    MenuHighScoreLabel.text = "Best: %d" % value

## Lifetime coins — shown in the top-left menu stats (not during a run).
func set_total_coin(value: int) -> void:
    MenuCoinLabel.text = "%d$" % value

# --- Rocket telemetry (called via the "hud" group from rocket.gd) ---

## Aim-timer fill, 0..1. Full when a drag starts, empties as time runs out.
func set_charge(ratio: float) -> void:
    ChargeBar.value = ratio

## Fuel fill, 0..1. Drains in flight, refills on asteroid hits.
func set_fuel(ratio: float) -> void:
    FuelBar.value = ratio
    var low := ratio <= LOW_FUEL_RATIO
    if low != _low_fuel:
        _set_low_fuel(low)

## Toggle the blinking low-fuel warning (red label + red screen vignette).
func _set_low_fuel(on: bool) -> void:
    _low_fuel = on
    if _low_fuel_tween and _low_fuel_tween.is_valid():
        _low_fuel_tween.kill()
    LowFuelLabel.visible = on
    if not on:
        _pulse_low_fuel(0.0)        # calm: label opaque, vignette off
        LowFuelLabel.modulate.a = 1.0
        return
    _low_fuel_tween = create_tween().set_loops()
    _low_fuel_tween.set_ignore_time_scale(true)
    _low_fuel_tween.set_trans(Tween.TRANS_SINE)
    _low_fuel_tween.tween_method(_pulse_low_fuel, 0.0, 1.0, 0.45)
    _low_fuel_tween.tween_method(_pulse_low_fuel, 1.0, 0.0, 0.45)

## Drive both warning visuals from one 0..1 value (0 = calm, 1 = full alarm).
func _pulse_low_fuel(v: float) -> void:
    LowFuelLabel.modulate.a = lerpf(0.15, 1.0, v)
    var mat = (low_fuel_overlay.material as ShaderMaterial) if low_fuel_overlay else null
    if mat:
        mat.set_shader_parameter("intensity", v * LOW_FUEL_INTENSITY)

## The rocket ran out of aim time and exploded — end the run.
func on_rocket_dead() -> void:
    _set_low_fuel(false)
    DeathScoreLabel.text = "Score: " + str(_score)
    $DeathPanel.show()

## Switch from the menu (top-left stats + bottom tabs) to the in-game HUD.
func enter_game_mode() -> void:
    MenuUI.hide()
    GameUI.show()

func _pause() -> void:
    get_tree().paused = true
    $PauseMenu.show()

func _resume() -> void:
    get_tree().paused = false
    $PauseMenu.hide()

func _restart() -> void:
    get_tree().paused = false      # unpause first, or the new scene starts frozen
    get_tree().reload_current_scene()

func _play_from_tabs() -> void:
    enter_game_mode()

func _open_settings() -> void:
    SettingsPanel.show()

func _close_settings() -> void:
    SettingsPanel.hide()

## Checkbox on = bus audible, off = bus muted.
func _on_sound_toggled(pressed: bool) -> void:
    AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not pressed)

func _on_music_toggled(pressed: bool) -> void:
    AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not pressed)

func _select_upgrade_tab() -> void:
    _select_bottom_tab("upgrade")

func _select_shop_tab() -> void:
    _select_bottom_tab("shop")

func _select_bottom_tab(tab: String) -> void:
    PlayTabButton.button_pressed = tab == "play"
    UpgradeTabButton.button_pressed = tab == "upgrade"
    ShopTabButton.button_pressed = tab == "shop"
