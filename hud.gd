extends CanvasLayer

var time := 0.0
var running := true
@onready var PauseButton = $PauseButton
@onready var ResumeButton = $PauseMenu/Panel/VBoxContainer/ResumeButton
@onready var RestartButton = $PauseMenu/Panel/VBoxContainer/RestartButton
@onready var DeathRestartButton = $DeathPanel/Panel/VBoxContainer/RestartButton

func _ready() -> void:
    add_to_group("hud")  # rocket.die() calls on_death() via this group
    PauseButton.pressed.connect(_pause)
    ResumeButton.pressed.connect(_resume)
    RestartButton.pressed.connect(_restart)
    DeathRestartButton.pressed.connect(_restart)

func _process(delta: float) -> void:
    if not running:
        return
    time += delta
    $Label.text = str(int(time))  # whole seconds survived; int() makes it tick up once per second

func on_death() -> void:
    running = false
    $PauseButton.hide()
    await get_tree().create_timer(0.7).timeout  # let the explosion play before the panel covers it
    $DeathPanel/Panel/VBoxContainer/ScoreLabel.text = "Score: " + str(int(time))
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
