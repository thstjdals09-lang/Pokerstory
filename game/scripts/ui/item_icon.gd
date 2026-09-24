extends Control
## Draws an item's placeholder art inside UI lists.

const ItemArt := preload("res://scripts/world/item_art.gd")

var placeholder := {}
var dimmed := false


func setup(item: Dictionary, p_dimmed: bool = false) -> void:
	placeholder = item.get("placeholder", {})
	dimmed = p_dimmed
	custom_minimum_size = Vector2(64, 64)
	queue_redraw()


func _draw() -> void:
	draw_style_box(UiKit.stylebox(Color("#3b2a20"), UiKit.BORDER, 2, 10, 0), Rect2(Vector2.ZERO, size))
	if dimmed:
		draw_string(preload("res://assets/fonts/ui_font.tres"), Vector2(0, size.y / 2 + 10), "?", HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, Color(1, 1, 1, 0.5))
	else:
		ItemArt.draw_item(self, placeholder, size / 2 + Vector2(0, 10), 1.1)
