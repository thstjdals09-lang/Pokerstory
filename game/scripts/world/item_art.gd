extends RefCounted
## Placeholder drawings for items, driven by the item's "placeholder" data.


static func draw_item(ci: CanvasItem, placeholder: Dictionary, center: Vector2, scale: float = 1.0, alpha: float = 1.0) -> void:
	var color := Color(str(placeholder.get("color", "#cccccc")))
	color.a *= alpha
	match str(placeholder.get("shape", "")):
		"lamp":
			_draw_lamp(ci, center, scale, color, alpha)
		"stool":
			var dark := color.darkened(0.35)
			ci.draw_rect(Rect2(center + Vector2(-12, -4) * scale, Vector2(24, 6) * scale), color)
			for x in [-10, 6]:
				ci.draw_rect(Rect2(center + Vector2(x, 2) * scale, Vector2(4, 14) * scale), dark)
		"cushion":
			ci.draw_circle(center, 14 * scale, color)
			ci.draw_circle(center, 14 * scale, color.darkened(0.3), false, 2.0 * scale)
			ci.draw_circle(center, 3 * scale, color.lightened(0.4))
		"wall_hanging":
			var pts := PackedVector2Array([center + Vector2(-12, -14) * scale, center + Vector2(12, -14) * scale,
				center + Vector2(12, 8) * scale, center + Vector2(0, 16) * scale, center + Vector2(-12, 8) * scale])
			ci.draw_colored_polygon(pts, color)
			ci.draw_line(center + Vector2(-16, -14) * scale, center + Vector2(16, -14) * scale, color.darkened(0.4), 3.0 * scale)
		"vase":
			ci.draw_circle(center + Vector2(0, 4) * scale, 11 * scale, color)
			ci.draw_rect(Rect2(center + Vector2(-5, -14) * scale, Vector2(10, 10) * scale), color)
			for i in 3:
				ci.draw_circle(center + Vector2(-6 + i * 6, -17) * scale, 4 * scale, Color(1, 0.85, 0.9, alpha))
		"coat":
			var body := PackedVector2Array([center + Vector2(-8, -14) * scale, center + Vector2(8, -14) * scale,
				center + Vector2(14, 14) * scale, center + Vector2(-14, 14) * scale])
			ci.draw_colored_polygon(body, color)
			ci.draw_line(center + Vector2(0, -12) * scale, center + Vector2(0, 14) * scale, color.darkened(0.4), 2.0 * scale)
		"card":
			ci.draw_rect(Rect2(center + Vector2(-10, -14) * scale, Vector2(20, 28) * scale), color)
			ci.draw_rect(Rect2(center + Vector2(-7, -11) * scale, Vector2(14, 22) * scale), Color(1, 1, 1, 0.5 * alpha), false, 1.5 * scale)
		"chip":
			ci.draw_circle(center, 13 * scale, color)
			ci.draw_circle(center, 13 * scale, Color(1, 0.95, 0.85, alpha), false, 3.0 * scale)
			ci.draw_circle(center, 5 * scale, Color(1, 0.95, 0.85, alpha))
		"stamp":
			ci.draw_rect(Rect2(center + Vector2(-12, -12) * scale, Vector2(24, 24) * scale), Color(1, 0.97, 0.9, alpha))
			ci.draw_rect(Rect2(center + Vector2(-8, -8) * scale, Vector2(16, 16) * scale), color)
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
