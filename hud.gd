extends CanvasLayer

var time := 0.0

func _process(delta: float) -> void:
    time += delta
    $Label.text = str(int(time))  # whole seconds survived; int() makes it tick up once per second
