class_name ObjectPool
extends Node

## A reusable FIFO object pool as a NODE: drop it in a scene, set `scene` and
## `size` in the inspector, and other scripts spawn()/despawn() through it (or
## react to its `spawned` / `despawned` signals).
##
## Pooled scenes MAY optionally provide:
##     signal died                   # if present, the pool auto-despawns on emit
##     func on_spawned() -> void     # called right after the object is handed out
##     func on_despawned() -> void   # called right before it returns to the pool
##
## Because the pool listens for `died` itself, pooled objects need no reference
## back to the pool — they just emit `died` when destroyed.

## Emitted right after an object is spawned (after its on_spawned() hook runs).
signal spawned(obj: Node)
## Emitted right after an object is despawned (after its on_despawned() hook runs).
signal despawned(obj: Node)

## The scene each pooled instance is built from.
@export var scene: PackedScene
## How many instances to pre-create.
@export var size: int = 16
## If true, spawn() creates extra instances when empty instead of returning null.
@export var allow_growth: bool = false
## Where spawned instances are parented. Defaults to this pool node itself.
@export var spawn_parent: Node

## Queue of ready-to-use (parked) instances. Front = next to spawn.
var _available: Array[Node] = []
## Every instance this pool created (for counts and teardown).
var _all: Array[Node] = []
var _initialized: bool = false


func _ready() -> void:
    _ensure_built()


## Pre-create the instances. Safe to call early (e.g. if another node's _ready
## spawns from us before ours has run) — it only builds once.
func _ensure_built() -> void:
    if _initialized:
        return
    _initialized = true
    if spawn_parent == null:
        spawn_parent = self
    if scene == null:
        push_warning("ObjectPool: no scene assigned.")
        return
    for i in size:
        _available.append(_create())


## Build one instance (kept out of the tree until spawned).
func _create() -> Node:
    var obj: Node = scene.instantiate()
    _all.append(obj)
    # Self-despawning: objects that report a "died" signal are returned to the
    # pool automatically, so they never need to know about this pool.
    if obj.has_signal("died"):
        obj.died.connect(despawn.bind(obj))
    return obj


## Take an instance from the pool and add it to the tree. Listen to the
## `spawned` signal to position it. Returns null if empty and growth is off.
func spawn() -> Node:
    _ensure_built()
    if _available.is_empty():
        if not allow_growth:
            return null
        _available.append(_create())
    var obj: Node = _available.pop_front()  # dequeue (FIFO)
    spawn_parent.add_child(obj)
    if obj.has_method("on_spawned"):
        obj.on_spawned()
    spawned.emit(obj)
    return obj


## Return an instance to the pool: removed from the tree and queued for reuse.
## Called automatically when a pooled object emits `died`.
func despawn(obj: Node) -> void:
    if obj == null or _available.has(obj):
        return
    if obj.has_method("on_despawned"):
        obj.on_despawned()
    if obj.get_parent() != null:
        obj.get_parent().remove_child(obj)
    _available.append(obj)  # enqueue
    despawned.emit(obj)


## How many instances are currently parked and ready to spawn.
func available_count() -> int:
    return _available.size()


## How many instances are currently spawned (in use).
func active_count() -> int:
    return _all.size() - _available.size()


## Total instances this pool manages.
func total() -> int:
    return _all.size()


func _notification(what: int) -> void:
    # Free any parked (out-of-tree) instances so they don't leak when the pool
    # is destroyed. Active ones are children and the engine frees those for us.
    if what == NOTIFICATION_PREDELETE:
        for obj in _all:
            if is_instance_valid(obj) and obj.get_parent() == null:
                obj.free()
