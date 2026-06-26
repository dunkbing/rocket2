extends Node2D

## Score/coin to display. Set via setup() before this is added to the tree.
var _score: int = 1
var _coin: int = 0


## Called by the asteroid that spawns this popup, before it enters the tree.
func setup(score: int, coin: int) -> void:
    _score = score
    _coin = coin
    if is_node_ready():
        _apply()


func _ready() -> void:
    _apply()


func _apply() -> void:
    $Label.text = "+%d" % _score
    $CoinLabel.text = "+%d$" % _coin
    $CoinLabel.visible = _coin > 0
