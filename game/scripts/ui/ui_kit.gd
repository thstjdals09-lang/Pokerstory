class_name UiKit
extends RefCounted
## Shared placeholder UI styling: warm paper panels and wooden buttons.

const PAPER := Color("#fff8ec")
const BORDER := Color("#8a5a3c")
const TEXT := Color("#3b2a20")
const ACCENT := Color("#c8553d")
const MUTED := Color("#8c7b6b")
const GOLD := Color("#e0a526")


static func stylebox(bg: Color, border: Color = BORDER, border_w: int = 3, radius: int = 12, pad: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb


static func panel(bg: Color = PAPER, pad: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stylebox(bg, BORDER, 3, 14, pad))
	return p


static func label(text: String, font_size: int = 18, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func wrap_label(text: String, font_size: int = 18, color: Color = TEXT) -> Label:
	var l := label(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, min_w: int = 150, focusable: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 44)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_stylebox_override("normal", stylebox(Color("#f3dfc1"), BORDER, 2, 10, 8))
	b.add_theme_stylebox_override("hover", stylebox(Color("#ffe9c7"), ACCENT, 2, 10, 8))
	b.add_theme_stylebox_override("pressed", stylebox(Color("#e8c79c"), ACCENT, 2, 10, 8))
	b.add_theme_stylebox_override("focus", stylebox(Color(0, 0, 0, 0), ACCENT, 3, 10, 8))
	b.add_theme_stylebox_override("disabled", stylebox(Color("#e3dbd0"), Color("#b5a898"), 2, 10, 8))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, TEXT)
	b.add_theme_color_override("font_disabled_color", Color("#9a8d80"))
	if not focusable:
		b.focus_mode = Control.FOCUS_NONE
	return b


static func dim_background() -> ColorRect:
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.07, 0.05, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return dim


## A full-screen container that centers its child.
static func centered(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(child)
	return c


static func clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
