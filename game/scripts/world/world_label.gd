class_name WorldLabel
extends RefCounted
## Outlined text labels for names and signs inside the world.


static func make(text: String, font_size: int = 14, color: Color = Color.WHITE, outline: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_constant_override("outline_size", 5)
		l.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.05, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
