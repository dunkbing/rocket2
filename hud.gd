extends CanvasLayer

## The shared PostFX vignette rect; its `alarm_intensity` red layer is pulsed
## when fuel is low.
@export var low_fuel_overlay: ColorRect

## Fuel fraction at/below which the low-fuel warning kicks in.
const LOW_FUEL_RATIO := 0.25
## Peak alpha of the red screen vignette at the top of each pulse.
const LOW_FUEL_INTENSITY := 0.2

@onready var GameUI: Control = $GameUI
@onready var LowFuelLabel: Label = $GameUI/LowFuelLabel
@onready var ScoreLabel: Label = $GameUI/ScoreLabel
@onready var CoinLabel: Label = $GameUI/CoinLabel
@onready var PauseButton = $GameUI/PauseButton
@onready var ResumeButton = $PauseMenu/Buttons/ResumeButton
@onready var RestartButton = $PauseMenu/Buttons/RestartButton
@onready var ChargeBar: ProgressBar = $GameUI/ChargeBar
@onready var FuelBar: ProgressBar = $GameUI/FuelBar
@onready var DeathRestartButton = $DeathPanel/Panel/VBoxContainer/RestartButton
@onready var DeathScoreLabel = $DeathPanel/Panel/VBoxContainer/ScoreLabel
@onready var MenuUI: Control = $MenuUI
@onready var MenuHighScoreLabel: Label = $MenuUI/MenuStats/HighScoreLabel
@onready var MenuCoinLabel: Label = $MenuUI/MenuStats/CoinLabel
@onready var PlayTabButton: Button = $MenuUI/BottomTabs/MarginContainer/HBoxContainer/PlayButton
@onready var UpgradeTabButton: Button = $MenuUI/BottomTabs/MarginContainer/HBoxContainer/UpgradeButton
@onready var ShopTabButton: Button = $MenuUI/BottomTabs/MarginContainer/HBoxContainer/ShopButton
@onready var SettingsButton: Button = $MenuUI/SettingsButton
@onready var SettingsPanel: Control = $MenuUI/SettingsPanel
@onready var SoundCheck: CheckBox = $MenuUI/SettingsPanel/Panel/VBoxContainer/SoundCheck
@onready var MusicCheck: CheckBox = $MenuUI/SettingsPanel/Panel/VBoxContainer/MusicCheck
@onready var LowSpecCheck: CheckBox = $MenuUI/SettingsPanel/Panel/VBoxContainer/LowSpecCheck
@onready var SettingsCloseButton: Button = $MenuUI/SettingsPanel/Panel/VBoxContainer/CloseButton
@onready var ShopPanel: Control = $MenuUI/ShopPanel
@onready var ShopGrid: GridContainer = $MenuUI/ShopPanel/Panel/VBoxContainer/ScrollContainer/GridContainer
@onready var ShopCloseButton: Button = $MenuUI/ShopPanel/Panel/VBoxContainer/CloseButton
@onready var UpgradePanel: Control = $MenuUI/UpgradePanel
@onready var FuelLevelLabel: Label = $MenuUI/UpgradePanel/Panel/VBoxContainer/UpgradeList/FuelRow/Info/Level
@onready var FuelBuyButton: Button = $MenuUI/UpgradePanel/Panel/VBoxContainer/UpgradeList/FuelRow/BuyButton
@onready var ChargeLevelLabel: Label = $MenuUI/UpgradePanel/Panel/VBoxContainer/UpgradeList/ChargeRow/Info/Level
@onready var ChargeBuyButton: Button = $MenuUI/UpgradePanel/Panel/VBoxContainer/UpgradeList/ChargeRow/BuyButton
@onready var SplitLevelLabel: Label = $MenuUI/UpgradePanel/Panel/VBoxContainer/UpgradeList/SplitRow/Info/Level
@onready var SplitBuyButton: Button = $MenuUI/UpgradePanel/Panel/VBoxContainer/UpgradeList/SplitRow/BuyButton
@onready var RocketLevelLabel: Label = $MenuUI/UpgradePanel/Panel/VBoxContainer/UpgradeList/RocketRow/Info/Level
@onready var RocketBuyButton: Button = $MenuUI/UpgradePanel/Panel/VBoxContainer/UpgradeList/RocketRow/BuyButton
@onready var UpgradeCloseButton: Button = $MenuUI/UpgradePanel/Panel/VBoxContainer/CloseButton

## Rocket skins, in the same order as the ShopGrid item buttons. The first is
## the free default (bird), always owned.
const ROCKET_SKINS: Array[String] = [
    "res://assets/rockets/default.png",
    "res://assets/rockets/bluefin.png",
    "res://assets/rockets/bulwark.png",
    "res://assets/rockets/comet_wing.png",
    "res://assets/rockets/crimson_lance.png",
    "res://assets/rockets/ghostray.png",
    "res://assets/rockets/starstreak.png",
]
## Unlock price (coins) for each skin, aligned with ROCKET_SKINS (default = free).
const ROCKET_PRICES: Array[int] = [0, 100, 250, 400, 600, 800, 1000]

## Latest values pushed from GameState; cached for the game-over panel.
var _score := 0
var _coin := 0

## True while the low-fuel warning is active; the looping pulse tween.
var _low_fuel := false
var _low_fuel_tween: Tween

## Gold outline applied to the currently-equipped shop tile.
var _equipped_style: StyleBoxFlat


func _ready() -> void:
    add_to_group("hud")  # the game state & rocket reach us via this group
    PauseButton.pressed.connect(_pause)
    ResumeButton.pressed.connect(_resume)
    RestartButton.pressed.connect(_restart)
    DeathRestartButton.pressed.connect(_restart)
    PlayTabButton.pressed.connect(_play_from_tabs)
    UpgradeTabButton.pressed.connect(_select_upgrade_tab)
    ShopTabButton.pressed.connect(_select_shop_tab)
    SettingsButton.pressed.connect(_open_settings)
    SettingsCloseButton.pressed.connect(_close_settings)
    ShopCloseButton.pressed.connect(_close_shop)
    FuelBuyButton.pressed.connect(_buy_upgrade.bind("fuel"))
    ChargeBuyButton.pressed.connect(_buy_upgrade.bind("charge"))
    SplitBuyButton.pressed.connect(_buy_upgrade.bind("split"))
    RocketBuyButton.pressed.connect(_buy_upgrade.bind("rocket"))
    UpgradeCloseButton.pressed.connect(_close_upgrades)
    # Each shop tile buys/equips its matching skin (order mirrors ROCKET_SKINS).
    var items := ShopGrid.get_children()
    for i in items.size():
        if i < ROCKET_SKINS.size():
            items[i].pressed.connect(_on_shop_item.bind(i))
    # Gold outline marking the equipped tile (applied in _refresh_shop).
    _equipped_style = StyleBoxFlat.new()
    _equipped_style.bg_color = Color(0.07, 0.09, 0.16, 1)  # match the tile bg
    _equipped_style.border_color = Color(1, 0.916, 0.537, 1)
    _equipped_style.set_border_width_all(3)
    _equipped_style.set_corner_radius_all(10)
    _equipped_style.set_content_margin_all(8)
    ScoreLabel.text = str(_score)
    CoinLabel.text = "%d$" % _coin
    # Sensible defaults in case the rocket's first emit beat us into the tree.
    ChargeBar.value = 1.0
    FuelBar.value = 1.0
    _select_bottom_tab("play")
    # GameState owns the audio settings; it pushes them via set_audio_settings()
    # once loaded, so we just wire the toggle handlers here.
    SoundCheck.toggled.connect(_on_sound_toggled)
    MusicCheck.toggled.connect(_on_music_toggled)
    LowSpecCheck.toggled.connect(_on_low_spec_toggled)
    GameUI.hide()  # menu is up at first; the in-game HUD stays hidden until Play

# --- Stat display (called via the "hud" group from GameState) ---

## Show the session score.
func set_score(value: int) -> void:
    _score = value
    ScoreLabel.text = str(value)

## Show the session coin count.
func set_coin(value: int) -> void:
    _coin = value
    CoinLabel.text = "%d$" % value

## Best score ever — shown in the top-left menu stats (not during a run).
func set_high_score(value: int) -> void:
    MenuHighScoreLabel.text = "Best: %d" % value

## Lifetime coins — shown in the top-left menu stats (not during a run).
func set_total_coin(value: int) -> void:
    MenuCoinLabel.text = "%d$" % value

# --- Rocket telemetry (called via the "hud" group from rocket.gd) ---

## Aim-timer fill, 0..1. Full when a drag starts, empties as time runs out.
func set_charge(ratio: float) -> void:
    ChargeBar.value = ratio

## Fuel fill, 0..1. Drains in flight, refills on asteroid hits.
func set_fuel(ratio: float) -> void:
    FuelBar.value = ratio
    var low := ratio <= LOW_FUEL_RATIO
    if low != _low_fuel:
        _set_low_fuel(low)

## Toggle the blinking low-fuel warning (red label + red screen vignette).
func _set_low_fuel(on: bool) -> void:
    _low_fuel = on
    if _low_fuel_tween and _low_fuel_tween.is_valid():
        _low_fuel_tween.kill()
    LowFuelLabel.visible = on
    if not on:
        _pulse_low_fuel(0.0)        # calm: label opaque, vignette off
        LowFuelLabel.modulate.a = 1.0
        return
    _low_fuel_tween = create_tween().set_loops()
    _low_fuel_tween.set_ignore_time_scale(true)
    _low_fuel_tween.set_trans(Tween.TRANS_SINE)
    _low_fuel_tween.tween_method(_pulse_low_fuel, 0.0, 1.0, 0.45)
    _low_fuel_tween.tween_method(_pulse_low_fuel, 1.0, 0.0, 0.45)

## Drive both warning visuals from one 0..1 value (0 = calm, 1 = full alarm).
func _pulse_low_fuel(v: float) -> void:
    LowFuelLabel.modulate.a = lerpf(0.15, 1.0, v)
    var mat = (low_fuel_overlay.material as ShaderMaterial) if low_fuel_overlay else null
    if mat:
        mat.set_shader_parameter("alarm_intensity", v * LOW_FUEL_INTENSITY)

## The rocket ran out of aim time and exploded — end the run.
func on_rocket_dead() -> void:
    _set_low_fuel(false)
    DeathScoreLabel.text = "Score: " + str(_score)
    $DeathPanel.show()
    $DeathPanel/AnimationPlayer.play("show")

## Switch from the menu (top-left stats + bottom tabs) to the in-game HUD.
func enter_game_mode() -> void:
    MenuUI.hide()
    GameUI.show()

## Hide the in-game pause button (called by the rocket the instant it dies).
func hide_pause_button() -> void:
    PauseButton.hide()

func _pause() -> void:
    get_tree().paused = true
    $PauseMenu.show()

func _resume() -> void:
    get_tree().paused = false
    $PauseMenu.hide()

func _restart() -> void:
    get_tree().paused = false      # unpause first, or the new scene starts frozen
    get_tree().reload_current_scene()

func _play_from_tabs() -> void:
    enter_game_mode()

func _open_settings() -> void:
    SettingsPanel.show()
    _play_panel_in(SettingsPanel)

func _close_settings() -> void:
    SettingsPanel.hide()

## Play a panel's pop-in animation. seek(0) forces the first frame immediately so
## there's no full-size flash before playback starts.
func _play_panel_in(panel: Control) -> void:
    var ap: AnimationPlayer = panel.get_node_or_null("AnimationPlayer")
    if ap:
        ap.play("show")
        ap.seek(0.0, true)

## Reflect the persisted audio settings into the checkboxes (no re-trigger).
func set_audio_settings(sound_on: bool, music_on: bool) -> void:
    SoundCheck.set_pressed_no_signal(sound_on)
    MusicCheck.set_pressed_no_signal(music_on)

## Checkbox on = audible, off = muted. GameState applies + persists it.
func _on_sound_toggled(pressed: bool) -> void:
    get_tree().call_group("game_state", "set_sound_enabled", pressed)

func _on_music_toggled(pressed: bool) -> void:
    get_tree().call_group("game_state", "set_music_enabled", pressed)

## Reflect the persisted low spec setting into the checkbox (no re-trigger).
func set_low_spec_setting(on: bool) -> void:
    LowSpecCheck.set_pressed_no_signal(on)

## Checkbox on = low spec: GameState turns off HDR/glow/PostFX and persists it.
func _on_low_spec_toggled(pressed: bool) -> void:
    get_tree().call_group("game_state", "set_low_spec_enabled", pressed)

func _select_upgrade_tab() -> void:
    _select_bottom_tab("upgrade")

func _select_shop_tab() -> void:
    _select_bottom_tab("shop")

## Close the shop by switching back to the Play tab.
func _close_shop() -> void:
    _select_bottom_tab("play")

## Close the upgrade panel by switching back to the Play tab.
func _close_upgrades() -> void:
    _select_bottom_tab("play")

## Buy the next level of an upgrade via GameState, then refresh the rows.
func _buy_upgrade(id: String) -> void:
    var game_state := get_tree().get_first_node_in_group("game_state")
    if game_state:
        game_state.buy_upgrade(id)
    _refresh_upgrades()

## Update both upgrade rows: level text + Buy button (cost / MAX / dimmed).
func _refresh_upgrades() -> void:
    var game_state := get_tree().get_first_node_in_group("game_state")
    if game_state == null:
        return
    _refresh_upgrade_row(game_state, "fuel", FuelLevelLabel, FuelBuyButton)
    _refresh_upgrade_row(game_state, "charge", ChargeLevelLabel, ChargeBuyButton)
    _refresh_upgrade_row(game_state, "split", SplitLevelLabel, SplitBuyButton)
    _refresh_upgrade_row(game_state, "rocket", RocketLevelLabel, RocketBuyButton)

func _refresh_upgrade_row(game_state, id: String, level_label: Label, buy_button: Button) -> void:
    var level: int = game_state.get_upgrade_level(id)
    var value_text: String = _format_upgrade_value(id, game_state.get_upgrade_value(id))
    level_label.text = "Lv %d/%d  (%s)" % [level, game_state.get_upgrade_max(), value_text]
    var cost: int = game_state.get_upgrade_cost(id)
    if cost < 0:
        buy_button.text = "MAX"
        buy_button.disabled = true
        buy_button.modulate = Color(1, 1, 1, 1)
    else:
        buy_button.text = "$%d" % cost
        buy_button.disabled = false
        buy_button.modulate = Color(1, 1, 1, 1) if game_state.total_coin >= cost else Color(1, 1, 1, 0.45)

## Human-readable current value per upgrade type.
func _format_upgrade_value(id: String, value: float) -> String:
    match id:
        "fuel": return "%d fuel" % int(value)
        "charge": return "%.1fs" % value
        "split", "rocket": return "%d%%" % roundi(value * 100.0)
    return ""

## Shop tile tapped: buy (if affordable) or equip via GameState, then refresh.
func _on_shop_item(index: int) -> void:
    var game_state := get_tree().get_first_node_in_group("game_state")
    if game_state == null:
        return
    game_state.buy_or_equip_skin(ROCKET_SKINS[index], ROCKET_PRICES[index])
    _refresh_shop()

## Update each tile's label to Equipped / Owned / price, dimming the unaffordable.
func _refresh_shop() -> void:
    var game_state := get_tree().get_first_node_in_group("game_state")
    if game_state == null:
        return
    var items := ShopGrid.get_children()
    for i in items.size():
        if i >= ROCKET_SKINS.size():
            continue
        var path: String = ROCKET_SKINS[i]
        var price: int = ROCKET_PRICES[i]
        var btn: Button = items[i]
        var equipped: bool = game_state.rocket_skin == path
        if equipped:
            btn.text = "Equipped"
            btn.modulate = Color(1, 1, 1, 1)
        elif game_state.is_skin_owned(path):
            btn.text = "Owned"
            btn.modulate = Color(1, 1, 1, 1)
        else:
            btn.text = "%d$" % price
            # Dim locked skins the player can't yet afford.
            btn.modulate = Color(1, 1, 1, 1) if game_state.total_coin >= price else Color(1, 1, 1, 0.45)
        _set_tile_highlight(btn, equipped)

## Apply (or remove) the gold equipped-outline across the button's states.
func _set_tile_highlight(btn: Button, on: bool) -> void:
    for state in ["normal", "hover", "pressed", "focus"]:
        if on:
            btn.add_theme_stylebox_override(state, _equipped_style)
        else:
            btn.remove_theme_stylebox_override(state)

func _select_bottom_tab(tab: String) -> void:
    PlayTabButton.button_pressed = tab == "play"
    UpgradeTabButton.button_pressed = tab == "upgrade"
    ShopTabButton.button_pressed = tab == "shop"
    ShopPanel.visible = tab == "shop"
    UpgradePanel.visible = tab == "upgrade"
    if tab == "shop":
        _refresh_shop()
        _play_panel_in(ShopPanel)
    elif tab == "upgrade":
        _refresh_upgrades()
        _play_panel_in(UpgradePanel)
