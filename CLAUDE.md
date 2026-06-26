# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`rocket2` is a Godot 4.7 (Mobile renderer, Jolt physics) 2D portrait game. The player slingshot-launches a rocket by dragging, then smashes it into asteroids for score. Built for a 288×512 portrait viewport.

## Commands

There is no build/test/lint tooling — this is a pure Godot project edited via the Godot editor. Common CLI invocations (requires `godot` on PATH, must be Godot 4.7):

```sh
godot --path .                       # open the project in the editor
godot --path . main_menu.tscn        # run the game from the main menu (the configured main scene)
godot --path . main.tscn             # run the gameplay scene directly, skipping the menu
godot --headless --path . --quit     # import assets / validate the project without a window
```

## Architecture

Scene flow: `main_menu.tscn` (configured main scene) → Play → `main.tscn` (gameplay).

`main.tscn` wires together the whole game loop. Its nodes reference each other via exported `NodePath`s set in the scene, NOT via autoloads or singletons — there are none. Key wirings to preserve when editing:
- `Camera2D.target` → `Rocket`
- `AsteroidSpawner.rocket` → `Rocket`, and `AsteroidSpawner.asteroid_scene` → `asteroid.tscn`

Cross-node communication uses **Godot groups** rather than direct references, which keeps the rocket, asteroids, and HUD decoupled:
- Asteroids add themselves to the `"asteroids"` group; the rocket detects collisions and calls `explode()` on any contacted body in that group.
- The HUD adds itself to the `"hud"` group; a destroyed asteroid calls `get_tree().call_group("hud", "on_asteroid_destroyed")` to bump the score.

### Core mechanics

- **Rocket** (`rocket.gd`, `RigidBody2D`): Stays `freeze = true` until launched. Drag-anywhere slingshot — drag direction (not press location) sets launch velocity (`drag * power`, capped at `max_launch_speed`). While aiming it simulates and draws a dotted trajectory in `_draw()` (gravity-integrated, points stored in local space). `_integrate_forces` keeps the nose aligned to velocity during flight. Uses `contact_monitor` + `body_entered` to destroy asteroids on impact. Gameplay tuning is exposed via `@export` vars.
- **Asteroid pooling** (`asteroid_spawner.gd` + `asteroid.gd`): The spawner pre-instances a fixed pool (`pool_size`) and never frees them. On destruction an asteroid is `deactivate()`d (hidden + collision disabled), waits `respawn_delay`, then is re-`_activate()`d at a new ring position around the rocket (`spawn_min_radius`..`spawn_max_radius`), avoiding overlap with live asteroids. Asteroids are `StaticBody2D` and self-report into the `"asteroids"` group.
- **Explosion** (`explosion.gd`, `GPUParticles2D`): One-shot effect added to `get_tree().current_scene` (so it outlives the recycled asteroid), self-frees after the longest child emitter finishes.
- **HUD** (`hud.gd`, `CanvasLayer`): Tracks score and owns pause/resume/restart. Restart calls `reload_current_scene()` — note it unpauses first, since a reloaded scene would otherwise start frozen.
- **Camera** (`follow_camera.gd`): Follows the rocket's position only (never rotation) in `_physics_process`.

### Physics gotchas

- Asteroid `explode()` defers tree mutation via `call_deferred` because it runs inside a physics collision callback. Collision shape enable/disable similarly uses `set_deferred`. Preserve this pattern when touching collision/scene-tree changes during physics.
- Physics layers (`project.godot`): layer 1 = `rocket`, layer 2 = `asteroid`.
- Input action `thrust` (Space / left mouse) is defined but launching is currently driven directly by mouse button + motion events in `rocket.gd`.

## Conventions

- GDGuide style as in existing files: 4 spaces for indentation; `snake_case` files and methods; private members prefixed `_`; tuning values exposed as `@export` with `##` doc comments. Each script `extends` a Godot node type (no `class_name` declarations in use).
- Keep code comments short and concise. Prefer clear names and small functions over long explanatory comments.
- Do not automatically edit `.tscn` scene files directly. Prefer guiding scene changes through the Godot editor, or ask for explicit confirmation before making scene-file edits.
- Every `.gd` has a paired `.gd.uid`; every `.tscn`/resource is referenced by `uid://` — don't hand-edit UIDs, and keep script/scene UID references intact when renaming.
