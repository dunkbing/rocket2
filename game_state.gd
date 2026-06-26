extends Node

## Holds the stats for the current game session. Other nodes report stat changes
## through the "game_state" group; this then pushes the values to the HUD.

var score: int = 0
var coin: int = 0


func _ready() -> void:
    add_to_group("game_state")
    _push()


## Add an asteroid's reward when it's destroyed (called via the group).
func add_stats(score_amount: int, coin_amount: int) -> void:
    score += score_amount
    coin += coin_amount
    _push()


## Send the current values to the HUD for display.
func _push() -> void:
    get_tree().call_group("hud", "set_score", score)
    get_tree().call_group("hud", "set_coin", coin)
