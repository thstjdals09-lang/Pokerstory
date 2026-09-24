extends RefCounted
## Placeholder drawings for items, driven by the item's "placeholder" data.


static func draw_item(ci: CanvasItem, placeholder: Dictionary, center: Vector2, scale: float = 1.0, alpha: float = 1.0) -> void:
	var color := Color(str(placeholder.get("color", "#cccccc")))
	color.a *= alpha
	match str(placeholder.get("shape", "")):
		"lamp":
			_draw_lamp(ci, center, scale, color, alpha)
		_:
			ci.draw_rect(Rect2(center - Vector2(14, 14) * scale, Vector2(28, 28) * scale), color)


static func _draw_lamp(ci: CanvasItem, c: Vector2, s: float, light: Color, alpha: float) -> void:
	var dark := Color(0.29, 0.2, 0.14, alpha)
	for i in 4:
		ci.draw_circle(c + Vector2(0, -12) * s, (34 - i * 7) * s, Color(light.r, light.g, light.b, 0.1 * alpha))
	ci.draw_rect(Rect2(c + Vector2(-10, 12) * s, Vector2(20, 5) * s), dark)
	ci.draw_rect(Rect2(c + Vector2(-2, -6) * s, Vector2(4, 18) * s), dark)
	var shade := PackedVector2Array([
		c + Vector2(-13, -6) * s, c + Vector2(13, -6) * s,
		c + Vector2(7, -22) * s, c + Vector2(-7, -22) * s,
	])
	ci.draw_colored_polygon(shade, light)
	ci.draw_polyline(shade + PackedVector2Array([shade[0]]), dark, 1.5 * s)
	ci.draw_circle(c + Vector2(0, -13) * s, 3 * s, dark)
