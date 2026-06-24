extends GPUParticles2D

# One-shot explosion: fire this emitter plus any GPUParticles2D children (e.g.
# a smoke/puff layer), then free the whole thing once the longest burst is done.


func _ready() -> void:
    emitting = true
    var longest: float = lifetime
    for child in get_children():
        if child is GPUParticles2D:
            child.emitting = true
            longest = maxf(longest, child.lifetime)
    # Small buffer so the last particles finish fading before we free.
    await get_tree().create_timer(longest + 0.3).timeout
    queue_free()
