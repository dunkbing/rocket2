extends CanvasLayer

var score := 0
@onready var PauseButton = $PauseButton
@onready var ResumeButton = $PauseMenu/Panel/VBoxContainer/ResumeButton
@onready var RestartButton = $PauseMenu/Panel/VBoxContainer/RestartButton

func _ready() -> void:
    add_to_group("hud")  # asteroids reach us via this group
    PauseButton.pressed.connect(_pause)
    ResumeButton.pressed.connect(_resume)
    RestartButton.pressed.connect(_restart)
    $Label.text = str(score)

# Called by each asteroid when the rocket destroys it.
func on_asteroid_destroyed() -> void:
    score += 1
    $Label.text = str(score)

func _pause() -> void:
    get_tree().paused = true
    $PauseMenu.show()

func _resume() -> void:
    get_tree().paused = false
    $PauseMenu.hide()

func _restart() -> void:
    get_tree().paused = false      # unpause first, or the new scene starts frozen
    get_tree().reload_current_scene()
