extends CanvasLayer

@onready var GameUI: Control = $GameUI
@onready var ScoreLabel: Label = $GameUI/ScoreLabel
@onready var CoinLabel: Label = $GameUI/CoinLabel
@onready var PauseButton = $GameUI/PauseButton
@onready var ResumeButton = $PauseMenu/Panel/VBoxContainer/ResumeButton
@onready var RestartButton = $PauseMenu/Panel/VBoxContainer/RestartButton
@onready var ChargeBar: ProgressBar = $GameUI/ChargeBar
@onready var FuelBar: ProgressBar = $GameUI/FuelBar
@onready var DeathRestartButton = $DeathPanel/Panel/VBoxContainer/RestartButton
@onready var DeathScoreLabel = $DeathPanel/Panel/VBoxContainer/ScoreLabel
@onready var BottomTabs: Control = $BottomTabs
@onready var PlayTabButton: Button = $BottomTabs/Panel/MarginContainer/HBoxContainer/PlayButton
@onready var UpgradeTabButton: Button = $BottomTabs/Panel/MarginContainer/HBoxContainer/UpgradeButton
@onready var ShopTabButton: Button = $BottomTabs/Panel/MarginContainer/HBoxContainer/ShopButton

## Latest values pushed from GameState; cached for the game-over panel.
var _score := 0
var _coin := 0


func _ready() -> void:
    add_to_group("hud")  # the game state & rocket reach us via this group
    PauseButton.pressed.connect(_pause)
    ResumeButton.pressed.connect(_resume)
    RestartButton.pressed.connect(_restart)
    DeathRestartButton.pressed.connect(_restart)
    PlayTabButton.pressed.connect(_play_from_tabs)
    UpgradeTabButton.pressed.connect(_select_upgrade_tab)
    ShopTabButton.pressed.connect(_select_shop_tab)
    ScoreLabel.text = str(_score)
    CoinLabel.text = "%d$" % _coin
    # Sensible defaults in case the rocket's first emit beat us into the tree.
    ChargeBar.value = 1.0
    FuelBar.value = 1.0
    _select_bottom_tab("play")
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

# --- Rocket telemetry (called via the "hud" group from rocket.gd) ---

## Aim-timer fill, 0..1. Full when a drag starts, empties as time runs out.
func set_charge(ratio: float) -> void:
    ChargeBar.value = ratio

## Fuel fill, 0..1. Drains in flight, refills on asteroid hits.
func set_fuel(ratio: float) -> void:
    FuelBar.value = ratio

## The rocket ran out of aim time and exploded — end the run.
func on_rocket_dead() -> void:
    DeathScoreLabel.text = "Score: " + str(_score)
    $DeathPanel.show()

## Hide bottom navigation once the run is active, and reveal the in-game HUD.
func hide_bottom_tabs() -> void:
    BottomTabs.hide()
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
    hide_bottom_tabs()

func _select_upgrade_tab() -> void:
    _select_bottom_tab("upgrade")

func _select_shop_tab() -> void:
    _select_bottom_tab("shop")

func _select_bottom_tab(tab: String) -> void:
    PlayTabButton.button_pressed = tab == "play"
    UpgradeTabButton.button_pressed = tab == "upgrade"
    ShopTabButton.button_pressed = tab == "shop"
