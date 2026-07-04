extends Node

## Holds the stats for the current game session. Other nodes report stat changes
## through the "game_state" group; this then pushes the values to the HUD.
##
## High score and lifetime coins persist to disk so they survive between runs.

const SAVE_PATH := "user://save.cfg"

## Scene glow — disabled while low spec mode is on.
@export var world_environment: WorldEnvironment
## Post-processing overlays (vignette, chromatic aberration, glitch) — hidden
## while low spec mode is on.
@export var postfx: CanvasLayer

var score: int = 0
var coin: int = 0

## Best score ever reached (persisted).
var high_score: int = 0
## Total coins collected across all sessions (persisted).
var total_coin: int = 0

## Upgrade levels (0..MAX_UPGRADE_LEVEL), persisted. The applied stat values
## below are derived from these by _apply_upgrades().
const MAX_UPGRADE_LEVEL := 5
var fuel_level: int = 0
var charge_level: int = 0
var split_level: int = 0
var rocket_level: int = 0

## Upgrade tuning: applied value = base + per_level * level; next level costs
## cost_step * next_level coins.
const _FUEL_BASE := 30.0
const _FUEL_PER_LEVEL := 20.0
const _FUEL_COST_STEP := 80
const _CHARGE_BASE := 1.2
const _CHARGE_PER_LEVEL := 0.2
const _CHARGE_COST_STEP := 120
const _SPLIT_BASE := 0.0
const _SPLIT_PER_LEVEL := 0.1
const _SPLIT_COST_STEP := 100
const _ROCKET_BASE := 0.0
const _ROCKET_PER_LEVEL := 0.1
const _ROCKET_COST_STEP := 150

## Applied stats, derived from the levels.
var max_fuel: float = _FUEL_BASE
## Slow-mo charge time: real seconds you may hold a drag before timing out.
var charge_time: float = _CHARGE_BASE
## Chance (0..1) a destroyed asteroid splits into 4 — the spawner reads this.
var asteroid_split_chance: float = _SPLIT_BASE
## Chance (0..1), rolled in flight, to shoot a homing child rocket — the rocket reads this.
var child_rocket_chance: float = _ROCKET_BASE

## Audio settings (persisted). Mirrored onto the SFX / Music buses.
var sound_enabled: bool = true
var music_enabled: bool = true

## Low spec mode (persisted): turns off HDR 2D, glow, and the PostFX overlays.
## Defaults on for Android, off elsewhere (iOS/desktop).
var low_spec_enabled: bool = OS.get_name() == "Android"

## The free starter skin — always owned, never costs coins.
const DEFAULT_SKIN := "res://assets/rockets/default.png"
## Currently equipped rocket skin texture path (persisted).
var rocket_skin: String = DEFAULT_SKIN
## Texture paths of rocket skins the player has unlocked (persisted).
var owned_skins: PackedStringArray = PackedStringArray()


func _ready() -> void:
    add_to_group("game_state")
    _load()
    _apply_audio()  # mute/unmute the buses to match the loaded settings
    _apply_low_spec()
    # Defer so the HUD / rocket have joined their groups before we reach them.
    _push.call_deferred()
    _apply_rocket_skin.call_deferred()
    _apply_upgrades.call_deferred()


## Derive the stat values from the levels and seed them onto the rocket.
func _apply_upgrades() -> void:
    max_fuel = _FUEL_BASE + _FUEL_PER_LEVEL * fuel_level
    charge_time = _CHARGE_BASE + _CHARGE_PER_LEVEL * charge_level
    # Read on demand by the spawner / rocket, so no group push needed.
    asteroid_split_chance = _SPLIT_BASE + _SPLIT_PER_LEVEL * split_level
    child_rocket_chance = _ROCKET_BASE + _ROCKET_PER_LEVEL * rocket_level
    get_tree().call_group("player", "set_max_fuel", max_fuel)
    get_tree().call_group("player", "set_charge_time", charge_time)


## Highest level any upgrade can reach.
func get_upgrade_max() -> int:
    return MAX_UPGRADE_LEVEL


## Current level (0..MAX_UPGRADE_LEVEL) of an upgrade ("fuel" or "charge").
func get_upgrade_level(id: String) -> int:
    match id:
        "fuel": return fuel_level
        "charge": return charge_level
        "split": return split_level
        "rocket": return rocket_level
    return 0


## The applied stat value an upgrade currently produces (for display).
func get_upgrade_value(id: String) -> float:
    match id:
        "fuel": return max_fuel
        "charge": return charge_time
        "split": return asteroid_split_chance
        "rocket": return child_rocket_chance
    return 0.0


## Coin cost of the next level, or -1 if the upgrade is already maxed.
func get_upgrade_cost(id: String) -> int:
    var level: int = get_upgrade_level(id)
    if level >= MAX_UPGRADE_LEVEL:
        return -1
    var next_level: int = level + 1
    match id:
        "fuel": return _FUEL_COST_STEP * next_level
        "charge": return _CHARGE_COST_STEP * next_level
        "split": return _SPLIT_COST_STEP * next_level
        "rocket": return _ROCKET_COST_STEP * next_level
    return -1


## Buy the next level of an upgrade if not maxed and the player can afford it.
func buy_upgrade(id: String) -> void:
    var cost: int = get_upgrade_cost(id)
    if cost < 0 or total_coin < cost:
        return
    total_coin -= cost
    match id:
        "fuel": fuel_level += 1
        "charge": charge_level += 1
        "split": split_level += 1
        "rocket": rocket_level += 1
    _apply_upgrades()
    _save()
    _push()  # refresh coin labels after spending


## Has the player unlocked this skin? The default is always owned.
func is_skin_owned(path: String) -> bool:
    return path == DEFAULT_SKIN or owned_skins.has(path)


## Shop tap: buy the skin if not owned (spending total_coin) then equip it.
## Does nothing if it's locked and the player can't afford it.
func buy_or_equip_skin(path: String, price: int) -> void:
    if not is_skin_owned(path):
        if total_coin < price:
            return  # can't afford — leave it locked
        total_coin -= price
        owned_skins.append(path)
    rocket_skin = path
    _apply_rocket_skin()
    _save()
    _push()  # refresh the coin labels after spending


## Persist + apply the chosen rocket skin (called by the shop).
func set_rocket_skin(path: String) -> void:
    rocket_skin = path
    _apply_rocket_skin()
    _save()


## Push the selected skin onto the live rocket (in the "player" group).
func _apply_rocket_skin() -> void:
    if rocket_skin != "":
        get_tree().call_group("player", "set_skin_path", rocket_skin)


## Persist + apply the sound-effects toggle (called by the HUD checkbox).
func set_sound_enabled(on: bool) -> void:
    sound_enabled = on
    _apply_audio()
    _save()


## Persist + apply the music toggle (called by the HUD checkbox).
func set_music_enabled(on: bool) -> void:
    music_enabled = on
    _apply_audio()
    _save()


## Persist + apply the low spec toggle (called by the HUD checkbox).
func set_low_spec_enabled(on: bool) -> void:
    low_spec_enabled = on
    _apply_low_spec()
    _save()


## Turn HDR 2D, glow, and the PostFX overlays on/off to match the setting.
func _apply_low_spec() -> void:
    var effects_on: bool = not low_spec_enabled
    get_viewport().use_hdr_2d = effects_on
    if world_environment and world_environment.environment:
        world_environment.environment.glow_enabled = effects_on
    if postfx:
        postfx.visible = effects_on


## Mirror the current settings onto the audio buses.
func _apply_audio() -> void:
    var sfx: int = AudioServer.get_bus_index("SFX")
    var music: int = AudioServer.get_bus_index("Music")
    if sfx != -1:
        AudioServer.set_bus_mute(sfx, not sound_enabled)
    if music != -1:
        AudioServer.set_bus_mute(music, not music_enabled)


## Add an asteroid's reward when it's destroyed (called via the group).
func add_stats(score_amount: int, coin_amount: int) -> void:
    score += score_amount
    coin += coin_amount
    total_coin += coin_amount
    if score > high_score:
        high_score = score
    _save()
    _push()


## Send the current values to the HUD for display.
func _push() -> void:
    get_tree().call_group("hud", "set_score", score)
    get_tree().call_group("hud", "set_coin", coin)
    get_tree().call_group("hud", "set_high_score", high_score)
    get_tree().call_group("hud", "set_total_coin", total_coin)
    get_tree().call_group("hud", "set_audio_settings", sound_enabled, music_enabled)
    get_tree().call_group("hud", "set_low_spec_setting", low_spec_enabled)


## Read the persisted high score / total coins / audio settings from disk.
func _load() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) != OK:
        return  # no save yet — keep the defaults
    high_score = int(cfg.get_value("stats", "high_score", 0))
    total_coin = int(cfg.get_value("stats", "total_coin", 0))
    sound_enabled = bool(cfg.get_value("audio", "sound", true))
    music_enabled = bool(cfg.get_value("audio", "music", true))
    # Fall back to the per-platform default when the save predates the setting.
    low_spec_enabled = bool(cfg.get_value("video", "low_spec", low_spec_enabled))
    rocket_skin = str(cfg.get_value("rocket", "skin", DEFAULT_SKIN))
    if rocket_skin == "":
        rocket_skin = DEFAULT_SKIN  # normalize old saves that stored ""
    owned_skins = cfg.get_value("rocket", "owned", PackedStringArray())
    fuel_level = int(cfg.get_value("upgrades", "fuel_level", 0))
    charge_level = int(cfg.get_value("upgrades", "charge_level", 0))
    split_level = int(cfg.get_value("upgrades", "split_level", 0))
    rocket_level = int(cfg.get_value("upgrades", "rocket_level", 0))


## Write the persisted stats + audio settings + rocket skin + upgrades to disk.
func _save() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("stats", "high_score", high_score)
    cfg.set_value("stats", "total_coin", total_coin)
    cfg.set_value("audio", "sound", sound_enabled)
    cfg.set_value("audio", "music", music_enabled)
    cfg.set_value("video", "low_spec", low_spec_enabled)
    cfg.set_value("rocket", "skin", rocket_skin)
    cfg.set_value("rocket", "owned", owned_skins)
    cfg.set_value("upgrades", "fuel_level", fuel_level)
    cfg.set_value("upgrades", "charge_level", charge_level)
    cfg.set_value("upgrades", "split_level", split_level)
    cfg.set_value("upgrades", "rocket_level", rocket_level)
    cfg.save(SAVE_PATH)
