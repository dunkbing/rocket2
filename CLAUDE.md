# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`rocket2` is a Godot 4.7 (Mobile renderer, Jolt physics) 2D portrait game for iOS/Android. The player slingshot-launches a rocket by dragging, smashes asteroids for score/coins/fuel, and dodges hazards. Designed for a 288×512 portrait viewport (`canvas_items` stretch, `expand` aspect); `viewport/hdr_2d` is on so HDR colors (>1.0) bloom via the WorldEnvironment glow.

## Commands

There is no build/test/lint tooling — this is a pure Godot project edited via the Godot editor. `godot` is not on PATH on this machine; use the app binary directly (must be Godot 4.7):

```sh
alias godot=/Applications/Godot.app/Contents/MacOS/Godot
godot --path .                       # open the project in the editor
godot --path . main.tscn             # run the game (also the configured main scene)
godot --headless --path . --quit     # import assets / validate the project without a window
godot --headless --path . --export-release "Android" build/rocket.apk
godot --headless --path . --export-release "iOS" ios/rocket.ipa
```

Export presets live in `export_presets.cfg` (Android + iOS). The `ios/` and `build/` output dirs are untracked.

## Architecture

Everything runs inside `main.tscn` — there is no separate menu scene. The HUD (`hud.tscn`, CanvasLayer) hosts both the menu (`MenuUI`: stats, settings, bottom tabs for Play/Upgrades/Shop) and the in-game UI (`GameUI`); the rocket's first drag calls `enter_game_mode()` to swap them.

There are NO autoloads/singletons. Nodes are wired two ways — preserve both patterns:

1. **Exported `NodePath`s set in `main.tscn`**: `Camera2D.target` → Rocket, `Spawner.rocket`/`Spawner.base`, `Rocket.vignette`/`camera`/`glitch_overlay` (PostFX rects), `HUD.low_fuel_overlay`, `BackgroundField.target` → Rocket.
2. **Godot groups + `call_group`** for cross-cutting messages:

| Group | Who joins | Called for |
|---|---|---|
| `asteroids` | all asteroid variants | rocket hit detection → `explode()` |
| `hazards` | red asteroid | kills the rocket on contact |
| `gold` | gold asteroid | extra coin ding on hit |
| `blackholes` | black holes | spawner spacing rules |
| `player` | rocket | upgrade/skin pushes from GameState, minimap |
| `hud` | HUD | score/fuel/charge display, game-over flow |
| `game_state` | GameState | stat changes, audio settings, upgrade rolls |
| `asteroid_spawner` | Spawner | destroyed asteroids request splits |

### Core systems

- **Rocket** (`rocket.gd`, RigidBody2D): frozen until launched; drag-anywhere slingshot (drag vector × `power`, capped). While aiming: slow-mo (`Engine.time_scale`), camera zoom-out, vignette, and a real-time charge timer — if it empties before release, the rocket dies. Fuel drains in flight, refills per asteroid smashed; empty fuel blocks launching. On hit it re-applies velocity in `_integrate_forces` (punch-through, upward-biased). Death: explosion, camera shake, one-shot screen glitch, then Game Over popup.
- **Pooling** (`object_pool.gd`, `class_name ObjectPool`): generic pool node; pooled scenes optionally implement `signal died` + `on_spawned()/on_despawned()`. The Spawner owns four pools (normal/red/gold asteroids, black holes) and only decides placement: a ring around the rocket (`spawn_min_radius..max`), always off-screen, non-overlapping, extra clearance around black holes and the home `base`. Destroyed asteroids may split into 4 (chance from GameState, capped by `max_split_asteroids`).
- **GameState** (`game_state.gd`): session score/coins + persisted high score, lifetime coins, upgrade levels, owned/equipped rocket skins, and audio toggles (`user://save.cfg`). Upgrades (fuel, charge time, split chance, child-rocket chance) are derived stats pushed to the rocket via the `player` group.
- **HUD** (`hud.gd`): all UI incl. pause/restart, shop (skins), upgrades. Restart unpauses BEFORE `reload_current_scene()`. Top/bottom control offsets in `hud.tscn` include extra padding for iPhone notch/home-indicator — keep it when moving UI.
- **UiButton** (`ui_button.gd`, `@tool`): 9-patch button that REGENERATES its styleboxes in code (`_apply_style()`); per-variant patch margins live in `_PATCH_MARGINS`. Editing stylebox overrides on UiButton instances in `.tscn` files is futile — the script stomps them.
- **Background** (`background_field.gd`): stars/cloud emitters follow the rocket (world-space particles slide past = motion feel). The flat `BgColor` stays in a screen-fixed CanvasLayer.
- **PostFX**: vignette (+ red low-fuel alarm layer), chromatic aberration, and `screen_glitch.gdshader` (death flash). `glitch.gdshader` is the sprite-space variant used by the black hole core. Both derive from an MIT shader — keep the attribution headers.

### Physics gotchas

- Asteroid `explode()` and rocket death defer tree/physics mutations (`call_deferred`/`set_deferred`) because they run inside physics callbacks. Preserve this pattern.
- Physics layers: 1 = `rocket`, 2 = `asteroid`, 3 = `blackhole`, 4 = `blackhole_inner`.
- Asteroids are StaticBody2D; the rocket uses `contact_monitor` + `body_entered`.
- GPUParticles2D are culled by their local-space `visibility_rect` — emitters whose particles extend past ~100 px need an explicit larger rect or they blink out at screen edges (see black_hole.tscn).

## Conventions

- GDScript style as in existing files: 4-space indent; `snake_case`; private members prefixed `_`; tuning values as `@export` with `##` doc comments; scripts `extends` a node type (`ObjectPool` is the only `class_name`).
- Keep code comments short and concise. Prefer clear names and small functions over long explanatory comments.
- Do not edit `.tscn` scene files without an explicit request or confirmation; prefer guiding changes through the Godot editor. When hand-editing is approved, reference new resources by `path` and let the editor stamp the `uid` on next save.
- Every `.gd`/`.gdshader` has a paired `.uid`; every scene/resource is referenced by `uid://` — don't hand-edit UIDs, and keep script/scene UID references intact when renaming.
- New particle effects should follow the house pattern: `GradientTexture2D` radial dot (or default squares), `CurveTexture` scale-over-life, `color_ramp`/`color_initial_ramp` gradients, HDR values where bloom is wanted, and `preprocess` set for pooled scenes so respawns appear mid-effect.
