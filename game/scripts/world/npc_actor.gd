extends Node2D
## A resident placed in a location. Placeholder look comes from data/npcs.json "look".
## Shows a bouncing "!" when the resident has something new to say.

const BODY_RADIUS := 16.0

var npc_id := ""
var look := {}
var show_marker := false:
	set(value):
		show_marker = value
		queue_redraw()
var _t := 0.0


func setup(def: Dictionary) -> void:
	npc_id = def["id"]
	look = def.get("look", {})
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = BODY_RADIUS
	shape.shape = circle
	body.add_child(shape)
	add_child(body)
	var label := WorldLabel.make("%s · %s" % [def["name"], def.get("species", "")], 14, Color("#fff3d6"))
	label.position = Vector2(-90, -58)
	label.size = Vector2(180, 20)
	add_child(label)
	queue_redraw()


func _process(delta: float) -> void:
	if show_marker:
		_t += delta
		queue_redraw()


func _draw() -> void:
	var body := Color(str(look.get("color", "#cccccc")))
	var accent := Color(str(look.get("accent", "#ffffff")))
	var dark := Color(0.18, 0.12, 0.1)
	draw_circle(Vector2(0, 13), 14, Color(0, 0, 0, 0.2))
	match str(look.get("shape", "")):
		"fox":
			draw_colored_polygon(PackedVector2Array([Vector2(-15, -6), Vector2(-11, -26), Vector2(-3, -12)]), body)
			draw_colored_polygon(PackedVector2Array([Vector2(15, -6), Vector2(11, -26), Vector2(3, -12)]), body)
			draw_circle(Vector2(17, 9), 8, body)
			draw_circle(Vector2(21, 5), 4, accent)
			draw_circle(Vector2.ZERO, BODY_RADIUS + 2, dark)
			draw_circle(Vector2.ZERO, BODY_RADIUS, body)
			draw_circle(Vector2(0, 6), 8, accent)
		"fairy":
			draw_circle(Vector2(-14, -8), 10, Color(0.75, 0.9, 1.0, 0.8))
			draw_circle(Vector2(14, -8), 10, Color(0.75, 0.9, 1.0, 0.8))
			draw_circle(Vector2.ZERO, 14, dark)
			draw_circle(Vector2.ZERO, 12, body)
			for i in 6:
				var a := TAU * i / 6.0
				draw_line(Vector2.from_angle(a) * 7, Vector2.from_angle(a) * 12, accent, 3.0)
		"wizard":
			draw_circle(Vector2.ZERO, BODY_RADIUS + 2, dark)
			draw_circle(Vector2.ZERO, BODY_RADIUS, body)
			draw_colored_polygon(PackedVector2Array([Vector2(-19, -8), Vector2(19, -8), Vector2(4, -42)]), body.darkened(0.3))
			draw_circle(Vector2(4, -42), 3, Color("#ffd27a"))
		_:
			draw_circle(Vector2.ZERO, BODY_RADIUS, body)
	draw_circle(Vector2(-5, -2), 2.2, dark)
	draw_circle(Vector2(5, -2), 2.2, dark)
	if show_marker:
		var y := -80.0 + sin(_t * 5.0) * 4.0
		draw_circle(Vector2(0, y), 11, Color("#ffd23f"))
		draw_circle(Vector2(0, y), 11, dark, false, 2.0)
		draw_rect(Rect2(-1.8, y - 7, 3.6, 8), dark)
		draw_circle(Vector2(0, y + 5), 2, dark)
