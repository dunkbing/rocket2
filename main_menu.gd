extends Control

func _ready() -> void:
    $PlayButton.pressed.connect(_play)

func _play() -> void:
    get_tree().change_scene_to_file("res://main.tscn")
