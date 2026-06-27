extends Node

## Holds the stats for the current game session. Other nodes report stat changes
## through the "game_state" group; this then pushes the values to the HUD.
##
## High score and lifetime coins persist to disk so they survive between runs.

const SAVE_PATH := "user://save.cfg"

var score: int = 0
var coin: int = 0

## Best score ever reached (persisted).
var high_score: int = 0
## Total coins collected across all sessions (persisted).
var total_coin: int = 0


func _ready() -> void:
    add_to_group("game_state")
    _load()
    # Defer so the HUD has joined the "hud" group before we push to it.
    _push.call_deferred()


## Add an asteroid's reward when it's destroyed (called via the group).
func add_stats(score_amount: int, coin_amount: int) -> void:
    score += score_amount
    coin += coin_amount
    total_coin += coin_amount
    if score > high_score:
        high_score = score
    _save()
    _push()


## Send the current values to the HUD for display.
func _push() -> void:
    get_tree().call_group("hud", "set_score", score)
    get_tree().call_group("hud", "set_coin", coin)
    get_tree().call_group("hud", "set_high_score", high_score)
    get_tree().call_group("hud", "set_total_coin", total_coin)


## Read the persisted high score / total coins from disk.
func _load() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) != OK:
        return  # no save yet — keep the defaults
    high_score = int(cfg.get_value("stats", "high_score", 0))
    total_coin = int(cfg.get_value("stats", "total_coin", 0))


## Write the persisted stats back to disk.
func _save() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("stats", "high_score", high_score)
    cfg.set_value("stats", "total_coin", total_coin)
    cfg.save(SAVE_PATH)
