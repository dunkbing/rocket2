extends Node2D

const PIPE = preload("res://pipe.tscn")

func _ready() -> void:
    $Timer.timeout.connect(_spawn)
    $Timer.start(1.5)

func _spawn() -> void:
    var p = PIPE.instantiate()
    p.position = Vector2(320, 256 + randf_range(-80.0, 80.0))  # right edge, random gap height
    add_child(p)
