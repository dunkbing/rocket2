extends Area2D

@export var speed := 100.0

func _ready() -> void:
    body_entered.connect(_on_hit)

func _process(delta: float) -> void:
    position.x -= speed * delta
    if position.x < -50:
        queue_free()

func _on_hit(_body: Node) -> void:
    get_tree().reload_current_scene()  # ponytail: scene reload = game over + reset, swap for a real UI when you add one
