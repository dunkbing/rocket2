extends Node

## Holds the stats for the current game session. Other nodes report stat changes
## through the "game_state" group; this then pushes the values to the HUD.
##
## High score and lifetime coins persist to disk so they survive between runs.

const SAVE_PATH := "user://save.cfg"

var score: int = 0
var coin: int = 0

## Best score ever reached (persisted).
var high_score: int = 0
## Total coins collected across all sessions (persisted).
var total_coin: int = 0

## Chance (0..1) that a destroyed asteroid splits into 4 new ones. Kept here so
## it can be raised by upgrades later; the asteroid spawner reads it on each hit.
@export_range(0.0, 1.0, 0.05) var asteroid_split_chance: float = 0.25

## Audio settings (persisted). Mirrored onto the SFX / Music buses.
var sound_enabled: bool = true
var music_enabled: bool = true


func _ready() -> void:
    add_to_group("game_state")
    _load()
    _apply_audio()  # mute/unmute the buses to match the loaded settings
    # Defer so the HUD has joined the "hud" group before we push to it.
    _push.call_deferred()


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


## Read the persisted high score / total coins / audio settings from disk.
func _load() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) != OK:
        return  # no save yet — keep the defaults
    high_score = int(cfg.get_value("stats", "high_score", 0))
    total_coin = int(cfg.get_value("stats", "total_coin", 0))
    sound_enabled = bool(cfg.get_value("audio", "sound", true))
    music_enabled = bool(cfg.get_value("audio", "music", true))


## Write the persisted stats + audio settings back to disk.
func _save() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("stats", "high_score", high_score)
    cfg.set_value("stats", "total_coin", total_coin)
    cfg.set_value("audio", "sound", sound_enabled)
    cfg.set_value("audio", "music", music_enabled)
    cfg.save(SAVE_PATH)
