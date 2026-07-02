@tool
extends Button

## Reusable 9-patch button. Pick a color variant in the inspector; because this
## is a @tool script it re-skins live in the editor the moment you change it.
## Text is styled (white fill + navy outline + drop shadow) to match the art.

enum Variant { BLUE, LAVENDER, YELLOW }

const _TEXTURES := {
    Variant.BLUE: "res://assets/ui/blue_button.png",
    Variant.LAVENDER: "res://assets/ui/lavender_button.png",
    Variant.YELLOW: "res://assets/ui/yellow_button.png",
}

## Default nine-patch border per variant, matched to each texture's size
## (blue is 64x64, lavender/yellow are 32x32).
const _PATCH_MARGINS := {
    Variant.BLUE: 20,
    Variant.LAVENDER: 10,
    Variant.YELLOW: 10,
}

## Which button image to show.
@export var variant: Variant = Variant.BLUE:
    set(value):
        variant = value
        _apply_style()

## Nine-patch border (px kept un-stretched at each edge/corner as it scales).
## 0 or less = automatic: the variant's default border from _PATCH_MARGINS.
@export var patch_margin: int = 0:
    set(value):
        patch_margin = value
        _apply_style()

## Inset between the frame and the label/icon (x = sides, y = top/bottom).
## Use a small value for icon-only buttons so the icon fills the face.
@export var content_margin: Vector2i = Vector2i(32, 26):
    set(value):
        content_margin = value
        _apply_style()

@export_group("Text")
## Fill color of the label.
@export var text_color: Color = Color(1, 1, 1, 1):
    set(value):
        text_color = value
        _apply_style()
## Outline color drawn around each glyph.
@export var outline_color: Color = Color(0.11, 0.13, 0.42, 1):
    set(value):
        outline_color = value
        _apply_style()
## Outline thickness in pixels.
@export var outline_size: int = 6:
    set(value):
        outline_size = value
        _apply_style()
## Soft drop shadow offset under the text.
@export var shadow_offset: Vector2i = Vector2i(0, 3):
    set(value):
        shadow_offset = value
        _apply_style()


func _ready() -> void:
    _apply_style()


func _apply_style() -> void:
    var texture := load(_TEXTURES[variant]) as Texture2D
    if texture == null:
        return
    _apply_boxes(texture)
    _apply_text()


## Per-state skins: brighten on hover, darken + nudge the label down on press.
func _apply_boxes(texture: Texture2D) -> void:
    add_theme_stylebox_override("normal", _make_box(texture, Color(1, 1, 1), 0))
    add_theme_stylebox_override("hover", _make_box(texture, Color(1.08, 1.08, 1.08), 0))
    add_theme_stylebox_override("pressed", _make_box(texture, Color(0.82, 0.82, 0.82), 3))
    add_theme_stylebox_override("focus", _make_box(texture, Color(1, 1, 1), 0))
    add_theme_stylebox_override("disabled", _make_box(texture, Color(0.7, 0.7, 0.7, 0.6), 0))


## Build one StyleBoxTexture: `tint` recolors the frame, `press_shift` slides the
## content down (positive) to fake the button being pushed in.
func _make_box(texture: Texture2D, tint: Color, press_shift: int) -> StyleBoxTexture:
    var box := StyleBoxTexture.new()
    box.texture = texture
    var margin: int = patch_margin if patch_margin > 0 else _PATCH_MARGINS[variant]
    box.set_texture_margin_all(margin)  # the nine-patch guides
    box.modulate_color = tint
    box.content_margin_left = content_margin.x
    box.content_margin_right = content_margin.x
    box.content_margin_top = content_margin.y + press_shift
    box.content_margin_bottom = content_margin.y - press_shift
    return box


## White label with a thick outline + drop shadow, held across every state.
func _apply_text() -> void:
    var dimmed := text_color
    dimmed.a *= 0.5
    add_theme_color_override("font_color", text_color)
    add_theme_color_override("font_hover_color", text_color)
    add_theme_color_override("font_pressed_color", text_color)
    add_theme_color_override("font_focus_color", text_color)
    add_theme_color_override("font_hover_pressed_color", text_color)
    add_theme_color_override("font_disabled_color", dimmed)
    add_theme_color_override("font_outline_color", outline_color)
    add_theme_constant_override("outline_size", outline_size)
    add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
    add_theme_constant_override("shadow_offset_x", shadow_offset.x)
    add_theme_constant_override("shadow_offset_y", shadow_offset.y)
