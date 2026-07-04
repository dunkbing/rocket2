extends Node2D

func _ready() -> void:
    if not $Music.playing:
        $Music.play()
