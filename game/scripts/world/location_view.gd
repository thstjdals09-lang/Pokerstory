extends Node2D
## Draws a location's placeholder graphics from its data definition:
## ground, paths, buildings with doors, decor, interior walls, and home furniture slots.

const ItemArt := preload("res://scripts/world/item_art.gd")
const UI_FONT := preload("res://assets/fonts/ui_font.tres")
const DARK := Color(0.2, 0.14, 0.1)

var loc := {}
var edit_mode := false
var selected_slot := ""
var preview_item := ""
var _slot_labels := {}
## [Label, conditions] for labels of decor that only exists in some world states.
var _conditional_labels: Array = []


func setup(p_loc: Dictionary) -> void:
	loc = p_loc
	for b in loc.get("buildings", []):
		var r := Geo.rect(b["rect"])
		var title := WorldLabel.make(b.get("label", ""), 18, Color.WHITE)
		title.position = r.position + Vector2(0, 14)
		title.size = Vector2(r.size.x, 28)
		add_child(title)
		if b.has("marker"):
			var door := Geo.vec(b["door"])
			var marker := WorldLabel.make(b["marker"], 16, Color("#ffe9a8"))
			marker.position = door + Vector2(-80, 44)
			marker.size = Vector2(160, 22)
			add_child(marker)
	for d in loc.get("decor", []):
		if not d.has("label"):
			continue
		var l := WorldLabel.make(d["label"], 14, Color("#fff3d6") if d.has("pos") else Color.WHITE)
		if d.has("rect"):
			var r := Geo.rect(d["rect"])
			l.position = r.position
			l.size = r.size
		else:
			l.position = Geo.vec(d["pos"]) + Vector2(-80, -64)
			l.size = Vector2(160, 18)
		add_child(l)
		if d.has("conditions"):
			_conditional_labels.append([l, d["conditions"]])
	for g in loc.get("gates", []):
		var gl := WorldLabel.make(g.get("label", ""), 15, Color("#fff3d6"))
		gl.position = Geo.vec(g["pos"]) + Vector2(-70, -48)
		gl.size = Vector2(140, 20)
		add_child(gl)
	for s in loc.get("slots", []):
		var r := Geo.rect(s["rect"])
		var l := WorldLabel.make(s["name"], 13, Color("#fff3d6"))
		l.position = r.position + Vector2(-20, r.size.y)
		l.size = Vector2(r.size.x + 40, 18)
		l.visible = false
		add_child(l)
		_slot_labels[s["id"]] = l
	if Game.state_changed.is_connected(queue_redraw) == false:
		Game.state_changed.connect(queue_redraw)
	queue_redraw()


func set_edit_state(p_edit: bool, p_slot: String, p_item: String) -> void:
	edit_mode = p_edit
	selected_slot = p_slot
	preview_item = p_item
	for s in loc.get("slots", []):
		_slot_labels[s["id"]].visible = edit_mode and _visible(s)
	queue_redraw()


func slot_at(point: Vector2) -> String:
	for s in loc.get("slots", []):
		if _visible(s) and Geo.rect(s["rect"]).grow(6).has_point(point):
			return s["id"]
	return ""


func _visible(d: Dictionary) -> bool:
	return not d.has("conditions") or (Game.state != null and Conditions.check(d["conditions"], Game.state))


func _draw() -> void:
	for pair in _conditional_labels:
		pair[0].visible = Game.state != null and Conditions.check(pair[1], Game.state)
	var size := Geo.vec(loc["size"])
	if loc.get("interior", false):
		_draw_interior_shell(size)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), _c(loc.get("ground", "#a3c982")))
		var inset := float(loc.get("bounds_inset", 20))
		draw_rect(Rect2(Vector2(inset, inset) * 0.5, size - Vector2(inset, inset)), Color("#8a6a48"), false, 4.0)
	for p in loc.get("paths", []):
		draw_rect(Geo.rect(p), _c(loc.get("path_color", "#e6d3a3")))
	for pl in loc.get("plazas", []):
		draw_circle(Geo.vec(pl["center"]), float(pl["radius"]), _c(pl["color"]))
	for d in loc.get("decor", []):
		if _visible(d):
			_draw_decor(d)
	for b in loc.get("buildings", []):
		_draw_building(b)
	for g in loc.get("gates", []):
		_draw_gate(Geo.vec(g["pos"]))
	for it in loc.get("interactables", []):
		if it.get("kind", "") == "object" and _visible(it):
			_draw_object(Geo.vec(it["pos"]), str(it.get("shape", "sign")))
	for s in loc.get("signs", []):
		_draw_sign(Geo.vec(s["pos"]))
	for e in loc.get("exits", []):
		_draw_exit(Geo.vec(e["pos"]))
	_draw_slots()


func _draw_interior_shell(size: Vector2) -> void:
	var inset := float(loc.get("bounds_inset", 28))
	draw_rect(Rect2(Vector2.ZERO, size), _c(loc.get("wall", "#8b6a50")))
	draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2), _c(loc.get("floor", "#dcbf94")))
	# floor boards
	var floor_col := _c(loc.get("floor", "#dcbf94")).darkened(0.08)
	var y := inset + 40.0
	while y < size.y - inset:
		draw_line(Vector2(inset, y), Vector2(size.x - inset, y), floor_col, 1.0)
		y += 40.0


func _draw_building(b: Dictionary) -> void:
	var r := Geo.rect(b["rect"])
	draw_rect(Rect2(r.position + Vector2(8, 10), r.size), Color(0, 0, 0, 0.18))
	draw_rect(r, _c(b["wall"]))
	var roof := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.42))
	draw_rect(roof, _c(b["roof"]))
	draw_line(roof.position + Vector2(0, roof.size.y), roof.end, DARK, 3.0)
	draw_rect(r, DARK, false, 3.0)
	# windows
	var wy := r.position.y + r.size.y * 0.55
	for wx in [r.position.x + 30, r.end.x - 72]:
		draw_rect(Rect2(wx, wy, 42, 34), Color("#bfe0f2"))
		draw_rect(Rect2(wx, wy, 42, 34), DARK, false, 2.0)
	# door on the bottom wall, doormat outside
	var door := Geo.vec(b["door"])
	var door_rect := Rect2(door.x - 22, door.y - 40, 44, 40)
	draw_rect(door_rect, Color("#7a4b2a"))
	draw_rect(door_rect, DARK, false, 2.0)
	draw_circle(door + Vector2(12, -20), 3, Color("#f2c94c"))
	draw_rect(Rect2(door.x - 28, door.y + 2, 56, 10), Color("#c8553d"))


func _draw_exit(pos: Vector2) -> void:
	draw_rect(Rect2(pos.x - 36, pos.y - 14, 72, 28), Color("#6b4a32"))
	draw_rect(Rect2(pos.x - 36, pos.y - 14, 72, 28), DARK, false, 2.0)
	draw_string(UI_FONT, Vector2(pos.x - 36, pos.y + 6), "출구 ↓", HORIZONTAL_ALIGNMENT_CENTER, 72, 14, Color.WHITE)


func _draw_gate(pos: Vector2) -> void:
	var wood := Color("#7a5230")
	draw_rect(Rect2(pos.x - 30, pos.y - 30, 8, 44), wood)
	draw_rect(Rect2(pos.x + 22, pos.y - 30, 8, 44), wood)
	draw_rect(Rect2(pos.x - 36, pos.y - 36, 72, 10), wood)
	draw_rect(Rect2(pos.x - 36, pos.y - 36, 72, 10), DARK, false, 2.0)
	draw_circle(pos + Vector2(0, -31), 5, Color("#f2c94c"))


## Placeholder marker for an interactable object (story spots, boards, tables).
func _draw_object(pos: Vector2, shape: String) -> void:
	match shape:
		"sign":
			_draw_sign(pos)
		"board":
			draw_rect(Rect2(pos.x - 34, pos.y - 44, 68, 40), Color("#b98a5a"))
			draw_rect(Rect2(pos.x - 34, pos.y - 44, 68, 40), DARK, false, 2.0)
			draw_rect(Rect2(pos.x - 26, pos.y - 38, 20, 26), Color("#fff8ec"))
			draw_rect(Rect2(pos.x + 2, pos.y - 36, 20, 22), Color("#ffe9a8"))
		"table":
			draw_circle(pos, 26, Color("#2f7a52"))
			draw_circle(pos, 26, Color("#6b4226"), false, 5.0)
		"scroll":
			draw_rect(Rect2(pos.x - 18, pos.y - 12, 36, 24), Color("#f3e2c0"))
			draw_rect(Rect2(pos.x - 18, pos.y - 12, 36, 24), DARK, false, 2.0)
		"spark":
			for i in 4:
				var a := TAU * i / 4.0
				draw_line(pos + Vector2.from_angle(a) * 4, pos + Vector2.from_angle(a) * 12, Color("#ffd23f"), 3.0)
			draw_circle(pos, 4, Color("#fff3a0"))


func _draw_sign(pos: Vector2) -> void:
	draw_rect(Rect2(pos.x - 3, pos.y - 6, 6, 26), Color("#6b4a32"))
	draw_rect(Rect2(pos.x - 26, pos.y - 30, 52, 26), Color("#d9b27c"))
	draw_rect(Rect2(pos.x - 26, pos.y - 30, 52, 26), DARK, false, 2.0)
	draw_string(UI_FONT, Vector2(pos.x - 26, pos.y - 11), "≡", HORIZONTAL_ALIGNMENT_CENTER, 52, 16, DARK)


func _draw_decor(d: Dictionary) -> void:
	match str(d.get("type", "")):
		"tree":
			var p := Geo.vec(d["pos"])
			var r := float(d["r"])
			draw_circle(p + Vector2(4, r * 0.5), r * 0.8, Color(0, 0, 0, 0.18))
			draw_rect(Rect2(p.x - 5, p.y, 10, r * 0.7), Color("#7a5230"))
			draw_circle(p, r, Color("#4f8a4b"))
			draw_circle(p + Vector2(-r * 0.25, -r * 0.25), r * 0.55, Color("#6aa860"))
		"fountain":
			var p := Geo.vec(d["pos"])
			var r := float(d["r"])
			draw_circle(p, r, Color("#b9ad9a"))
			draw_circle(p, r - 8, Color("#7fc4e0"))
			draw_circle(p, 10, Color("#b9ad9a"))
			var suits := ["♠", "♥", "♦", "♣"]
			for i in 4:
				var q := p + Vector2.from_angle(TAU * i / 4.0) * (r + 14)
				draw_string(UI_FONT, q + Vector2(-10, 7), suits[i], HORIZONTAL_ALIGNMENT_CENTER, 20, 18, DARK)
		"flowers":
			var r := Geo.rect(d["rect"])
			draw_rect(r, Color("#7aa65a"))
			var cols := [Color("#f28b82"), Color("#fbbc04"), Color("#ffffff"), Color("#c58af9")]
			var i := 0
			var x := r.position.x + 8
			while x < r.end.x - 4:
				draw_circle(Vector2(x, r.position.y + 12 + (i % 2) * 14), 4, cols[i % cols.size()])
				x += 13
				i += 1
		"rect":
			var r := Geo.rect(d["rect"])
			draw_rect(Rect2(r.position + Vector2(4, 6), r.size), Color(0, 0, 0, 0.16))
			draw_rect(r, _c(d.get("color", "#a9784f")))
			draw_rect(r, DARK, false, 2.0)
		"rug":
			var r := Geo.rect(d["rect"])
			draw_rect(r, _c(d.get("color", "#c97b63")))
			draw_rect(r.grow(-8), Color(1, 1, 1, 0.25), false, 2.0)
		"window":
			var r := Geo.rect(d["rect"])
			draw_rect(r, Color("#bfe0f2"))
			draw_rect(r, DARK, false, 2.0)
			draw_line(Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y), DARK, 2.0)
		"glow":
			var p := Geo.vec(d["pos"])
			var r := float(d["r"])
			for k in 5:
				draw_circle(p, r * (1.0 - k * 0.17), Color(1.0, 0.78, 0.45, 0.06))
		"felt_table":
			var p := Geo.vec(d["pos"])
			var r := float(d["r"])
			draw_circle(p + Vector2(6, 10), r, Color(0, 0, 0, 0.25))
			draw_circle(p, r, Color("#6b4226"))
			draw_circle(p, r - 12, Color("#2f7a52"))
			draw_circle(p, r - 30, Color(1, 1, 1, 0.08), false, 2.0)
			var suits := ["♠", "♥", "♦", "♣"]
			for i in 4:
				var q := p + Vector2.from_angle(TAU * i / 4.0) * (r - 30)
				draw_string(UI_FONT, q + Vector2(-10, 7), suits[i], HORIZONTAL_ALIGNMENT_CENTER, 20, 18, Color(1, 1, 1, 0.6))
		"board":
			var p := Geo.vec(d["pos"])
			draw_rect(Rect2(p.x - 30, p.y - 10, 6, 34), Color("#6b4a32"))
			draw_rect(Rect2(p.x + 24, p.y - 10, 6, 34), Color("#6b4a32"))
			var board := Rect2(p.x - 40, p.y - 44, 80, 38)
			draw_rect(board, Color("#b98a5a"))
			draw_rect(board, DARK, false, 2.0)
			draw_rect(Rect2(p.x - 32, p.y - 38, 22, 26), Color("#fff8ec"))
			draw_rect(Rect2(p.x - 4, p.y - 36, 18, 20), Color("#ffe9a8"))
			draw_circle(Vector2(p.x + 24, p.y - 28), 6, Color("#c8553d"))
		"house":
			var r := Geo.rect(d["rect"])
			draw_rect(Rect2(r.position + Vector2(8, 10), r.size), Color(0, 0, 0, 0.16))
			draw_rect(r, Color("#efe0c8"))
			draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.4)), Color("#9a7a6a"))
			draw_rect(r, DARK, false, 3.0)
		"postbox":
			var p := Geo.vec(d["pos"])
			draw_rect(Rect2(p.x - 3, p.y, 6, 26), Color("#6b4a32"))
			draw_rect(Rect2(p.x - 16, p.y - 22, 32, 26), Color("#c0392b"))
			draw_rect(Rect2(p.x - 16, p.y - 22, 32, 26), DARK, false, 2.0)
			draw_rect(Rect2(p.x - 9, p.y - 12, 18, 3), DARK)
		"booth", "stall":
			var r := Geo.rect(d["rect"]) if d.has("rect") else Rect2(Geo.vec(d["pos"]) - Vector2(60, 30), Vector2(120, 60))
			draw_rect(r, Color("#c9a37a"))
			draw_rect(Rect2(r.position, Vector2(r.size.x, 14)), Color("#c8553d"))
			draw_rect(r, DARK, false, 2.0)
		"awning", "garland":
			var r := Geo.rect(d["rect"])
			var x := r.position.x
			var i := 0
			while x < r.end.x:
				draw_rect(Rect2(x, r.position.y, 20, r.size.y), Color("#c8553d") if i % 2 == 0 else Color("#fff3d6"))
				x += 20
				i += 1
		"nook":
			var r := Geo.rect(d["rect"])
			draw_rect(r, Color("#a8845a"))
			draw_rect(r.grow(-10), Color("#c9a77a"))
			draw_rect(r, DARK, false, 2.0)
		"lantern_row":
			pass
		"lantern":
			var p := Geo.vec(d["pos"])
			draw_circle(p, 22, Color(1, 0.85, 0.45, 0.16))
			draw_rect(Rect2(p.x - 2, p.y, 4, 24), Color("#6b4a32"))
			draw_circle(p, 7, Color("#ffd27a"))
		"water":
			var r := Geo.rect(d["rect"])
			draw_rect(r, Color("#7fb8d6"))
			for k in 6:
				draw_line(Vector2(r.position.x + 40, r.position.y + 20 + k * 22), Vector2(r.end.x - 40, r.position.y + 20 + k * 22), Color(1, 1, 1, 0.18), 2.0)
		"deck":
			var r := Geo.rect(d["rect"])
			draw_rect(r, Color("#b88a5a"))
			var y := r.position.y + 14
			while y < r.end.y:
				draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color("#8a6a4a"), 1.0)
				y += 16
			draw_rect(r, DARK, false, 2.0)
		"garden":
			var r := Geo.rect(d["rect"])
			draw_rect(r, Color("#6aa860"))
			var suits := ["♠", "♥", "♦", "♣"]
			for k in 4:
				draw_string(UI_FONT, r.position + Vector2(30 + k * 70, 80), suits[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, 0.7))
		"circle":
			var p := Geo.vec(d["pos"])
			draw_circle(p + Vector2(4, 6), float(d["r"]), Color(0, 0, 0, 0.16))
			draw_circle(p, float(d["r"]), _c(d.get("color", "#c9a37a")))
		"item_display":
			var item: Dictionary = Game.data.items.get(d["item"], {})
			ItemArt.draw_item(self, item.get("placeholder", {}), Geo.vec(d["pos"]), 1.2)


func _draw_slots() -> void:
	for s in loc.get("slots", []):
		if not _visible(s):
			if _slot_labels.has(s["id"]):
				_slot_labels[s["id"]].visible = false
			continue
		var r := Geo.rect(s["rect"])
		var placed := ""
		if Game.state != null:
			placed = Game.state.placement_at(s["id"])
		if edit_mode:
			var selected: bool = s["id"] == selected_slot
			draw_rect(r, Color(1, 0.9, 0.5, 0.28 if selected else 0.12))
			var col := Color("#ffd23f") if selected else Color(1, 1, 1, 0.85)
			var w := 4.0 if selected else 2.0
			var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
			for i in 4:
				draw_dashed_line(corners[i], corners[(i + 1) % 4], col, w, 8.0)
		if placed != "":
			var item: Dictionary = Game.data.items.get(placed, {})
			ItemArt.draw_item(self, item.get("placeholder", {}), r.get_center() + Vector2(0, 8), 1.0)
		elif edit_mode and s["id"] == selected_slot and preview_item != "":
			var item: Dictionary = Game.data.items.get(preview_item, {})
			ItemArt.draw_item(self, item.get("placeholder", {}), r.get_center() + Vector2(0, 8), 1.0, 0.5)


static func _c(value) -> Color:
	return Color(str(value))
