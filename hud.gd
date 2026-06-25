extends CanvasLayer

@onready var PauseButton = $PauseButton
@onready var ResumeButton = $PauseMenu/Panel/VBoxContainer/ResumeButton
@onready var RestartButton = $PauseMenu/Panel/VBoxContainer/RestartButton
@onready var ChargeBar: ProgressBar = $ChargeBar
@onready var FuelBar: ProgressBar = $FuelBar
@onready var DeathRestartButton = $DeathPanel/Panel/VBoxContainer/RestartButton
@onready var DeathScoreLabel = $DeathPanel/Panel/VBoxContainer/ScoreLabel

var score := 0


func _ready() -> void:
    add_to_group("hud")  # the rocket & asteroids reach us via this group
    PauseButton.pressed.connect(_pause)
    ResumeButton.pressed.connect(_resume)
    RestartButton.pressed.connect(_restart)
    DeathRestartButton.pressed.connect(_restart)
    $Label.text = str(score)
    # Sensible defaults in case the rocket's first emit beat us into the tree.
    ChargeBar.value = 1.0
    FuelBar.value = 1.0

# Called by each asteroid when the rocket destroys it.
func on_asteroid_destroyed() -> void:
    score += 1
    $Label.text = str(score)

# --- Rocket telemetry (called via the "hud" group from rocket.gd) ---

## Aim-timer fill, 0..1. Full when a drag starts, empties as time runs out.
func set_charge(ratio: float) -> void:
    ChargeBar.value = ratio

## Fuel fill, 0..1. Drains in flight, refills on asteroid hits.
func set_fuel(ratio: float) -> void:
    FuelBar.value = ratio

## The rocket ran out of aim time and exploded — end the run.
func on_rocket_dead() -> void:
    DeathScoreLabel.text = "Score: " + str(score)
    $DeathPanel.show()

func _pause() -> void:
    get_tree().paused = true
    $PauseMenu.show()

func _resume() -> void:
    get_tree().paused = false
    $PauseMenu.hide()

func _restart() -> void:
    get_tree().paused = false      # unpause first, or the new scene starts frozen
    get_tree().reload_current_scene()
