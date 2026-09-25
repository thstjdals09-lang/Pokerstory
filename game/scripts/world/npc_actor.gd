extends Node2D
## A resident placed in a location. Placeholder look comes from data/npcs.json "look".
## Signal over the head (playability pass 1): "main" story (bouncing "!"), "story" (a resident's own
## story, speech bubble) or "request" (small "!"). A first greeting shows nothing.

const BODY_RADIUS := 16.0

var npc_id := ""
var look := {}
var marker_kind := "":
	set(value):
		marker_kind = value
		queue_redraw()
var show_marker: bool:
	get:
		return marker_kind != ""
var _t := 0.0
var _activity: Label = null
## Visual slice: sprite key from look.art (data/art.json); empty -> greybox shapes.
var art_key := ""
var _name_label: Label = null


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
	_name_label = label
	art_key = str(look.get("art", ""))
	if not ArtLib.has(art_key):
		art_key = ""
	else:
		label.text = str(def["name"])
		label.position = Vector2(-90, _sprite_top() - 24)
	queue_redraw()


## In art locations name tags appear only near the player (no permanent labels everywhere).
func set_name_visible(v: bool) -> void:
	if _name_label != null:
		_name_label.visible = v


func _sprite_top() -> float:
	return 16.0 - ArtLib.anchor(art_key).y


## What the resident is doing right now ("책 읽는 중"), shown under the name. Empty hides it.
func set_activity(text: String) -> void:
	if text == "":
		return
	_activity = WorldLabel.make(text, 12, Color("#ffe9b0"))
	_activity.position = Vector2(-90, 22)
	_activity.size = Vector2(180, 18)
	add_child(_activity)


func _process(delta: float) -> void:
	if show_marker or (art_key != "" and ArtLib.def(art_key).get("hover", false)):
		_t += delta
		queue_redraw()


func _draw() -> void:
	if art_key != "":
		_draw_art()
		return
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
		"elf":
			draw_colored_polygon(PackedVector2Array([Vector2(-16, -4), Vector2(-26, -12), Vector2(-12, -10)]), body)
			draw_colored_polygon(PackedVector2Array([Vector2(16, -4), Vector2(26, -12), Vector2(12, -10)]), body)
			draw_circle(Vector2.ZERO, BODY_RADIUS + 2, dark)
			draw_circle(Vector2.ZERO, BODY_RADIUS, body)
			draw_rect(Rect2(-14, -16, 28, 6), accent)
		"ghost":
			draw_circle(Vector2.ZERO, BODY_RADIUS + 2, Color(dark, 0.5))
			draw_circle(Vector2.ZERO, BODY_RADIUS, Color(body, 0.85))
			draw_rect(Rect2(-10, -2, 20, 14), accent)
			draw_string(preload("res://assets/fonts/ui_font.tres"), Vector2(-7, 11), "♣", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		"cat":
			draw_colored_polygon(PackedVector2Array([Vector2(-14, -8), Vector2(-12, -24), Vector2(-3, -13)]), body)
			draw_colored_polygon(PackedVector2Array([Vector2(14, -8), Vector2(12, -24), Vector2(3, -13)]), body)
			draw_circle(Vector2.ZERO, BODY_RADIUS + 2, dark)
			draw_circle(Vector2.ZERO, BODY_RADIUS, body)
			draw_line(Vector2(-14, 4), Vector2(-24, 2), dark, 1.5)
			draw_line(Vector2(14, 4), Vector2(24, 2), dark, 1.5)
		"rabbit":
			draw_rect(Rect2(-10, -34, 7, 22), body)
			draw_rect(Rect2(3, -34, 7, 22), body)
			draw_circle(Vector2.ZERO, BODY_RADIUS + 2, dark)
			draw_circle(Vector2.ZERO, BODY_RADIUS, body)
			draw_rect(Rect2(-8, -32, 3, 16), accent)
		"bird":
			draw_colored_polygon(PackedVector2Array([Vector2(-6, -14), Vector2(0, -30), Vector2(6, -14)]), accent)
			draw_circle(Vector2.ZERO, BODY_RADIUS + 2, dark)
			draw_circle(Vector2.ZERO, BODY_RADIUS, body)
			draw_colored_polygon(PackedVector2Array([Vector2(12, 0), Vector2(22, 4), Vector2(12, 8)]), accent)
		"mushroom":
			draw_circle(Vector2(0, 4), 12, accent)
			draw_colored_polygon(PackedVector2Array([Vector2(-22, -2), Vector2(22, -2), Vector2(14, -18), Vector2(-14, -18)]), body)
			draw_circle(Vector2(-6, -10), 3, Color.WHITE)
			draw_circle(Vector2(7, -12), 2.5, Color.WHITE)
		"bear":
			draw_circle(Vector2(-12, -13), 6, body)
			draw_circle(Vector2(12, -13), 6, body)
			draw_circle(Vector2.ZERO, BODY_RADIUS + 3, dark)
			draw_circle(Vector2.ZERO, BODY_RADIUS + 1, body)
			draw_circle(Vector2(0, 6), 7, accent)
		"stone":
			draw_rect(Rect2(-16, -16, 32, 34), dark)
			draw_rect(Rect2(-14, -14, 28, 30), body)
			draw_rect(Rect2(-10, 6, 20, 5), accent)
		"ribbon":
			draw_circle(Vector2(16, 10), 6, accent)
			draw_line(Vector2(10, 8), Vector2(24, 18), body, 4.0)
			draw_circle(Vector2.ZERO, BODY_RADIUS + 2, dark)
			draw_circle(Vector2.ZERO, BODY_RADIUS, body)
			draw_colored_polygon(PackedVector2Array([Vector2(-10, -16), Vector2(0, -12), Vector2(-10, -8)]), accent)
			draw_colored_polygon(PackedVector2Array([Vector2(10, -16), Vector2(0, -12), Vector2(10, -8)]), accent)
		"human":
			draw_circle(Vector2.ZERO, BODY_RADIUS + 2, dark)
			draw_circle(Vector2.ZERO, BODY_RADIUS, accent)
			draw_rect(Rect2(-16, -16, 32, 9), body)
			draw_rect(Rect2(-12, 8, 24, 8), body)
		_:
			draw_circle(Vector2.ZERO, BODY_RADIUS, body)
	draw_circle(Vector2(-5, -2), 2.2, dark)
	draw_circle(Vector2(5, -2), 2.2, dark)
	_draw_marker(-80.0)


func _draw_art() -> void:
	var hover: bool = bool(ArtLib.def(art_key).get("hover", false))
	var lift := (-10.0 + sin(_t * 3.0) * 3.0) if hover else 0.0
	draw_set_transform(Vector2(0, 16), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 17.0 if not hover else 12.0, Color(0, 0, 0, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ArtLib.draw(self, art_key, Vector2(0, 16 + lift))
	_draw_marker(_sprite_top() - 40.0)


## The signal over the head, centred at `top`: main story (bouncing "!"), a resident's own story
## (speech bubble) or a request (small "!").
func _draw_marker(top: float) -> void:
	var dark := Color(0.18, 0.12, 0.1)
	match marker_kind:
		"main":
			var y := top + sin(_t * 5.0) * 4.0
			draw_circle(Vector2(0, y), 11, Color("#ffd23f"))
			draw_circle(Vector2(0, y), 11, dark, false, 2.0)
			draw_rect(Rect2(-1.8, y - 7, 3.6, 8), dark)
			draw_circle(Vector2(0, y + 5), 2, dark)
		"story":
			var y := top + 4.0 + sin(_t * 2.0) * 2.0
			draw_colored_polygon(PackedVector2Array([Vector2(-4, y + 7), Vector2(4, y + 7), Vector2(-6, y + 14)]), Color.WHITE)
			draw_circle(Vector2(-6, y), 9, Color.WHITE)
			draw_circle(Vector2(6, y), 9, Color.WHITE)
			draw_rect(Rect2(-6, y - 9, 12, 18), Color.WHITE)
			for i in 3:
				draw_circle(Vector2(-6 + i * 6, y), 2, dark)
		"request":
			var y := top + 10.0
			draw_circle(Vector2(0, y), 7, Color("#ffd23f"))
			draw_circle(Vector2(0, y), 7, dark, false, 1.5)
			draw_rect(Rect2(-1.2, y - 4.5, 2.4, 5), dark)
			draw_circle(Vector2(0, y + 3), 1.3, dark)
