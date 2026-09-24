extends Node2D
## One playable location built from data/locations.json: drawing, collision, residents,
## doors, signs and other interactables, the player and the camera.
## Emits intents; Main decides what they do.

signal interacted(target: Dictionary)
signal focus_changed(target: Dictionary)
signal player_moved(distance: float)

const PlayerScript := preload("res://scripts/world/player.gd")
const NpcScript := preload("res://scripts/world/npc_actor.gd")
const LocationView := preload("res://scripts/world/location_view.gd")
const EVENING_TINT := Color(1.0, 0.8, 0.64)

var location_id := ""
var loc := {}
var player: CharacterBody2D
var view: Node2D
var camera: Camera2D
var canvas_modulate: CanvasModulate = null
## Each: {uid, kind, id, pos, radius, prompt, ...kind-specific fields}
var interactables: Array = []
var npc_nodes := {}
var focused := {}
var input_enabled := false:
	set(value):
		input_enabled = value
		if player:
			player.input_enabled = value
var _last_player_pos := Vector2.ZERO


func build(p_location_id: String, spawn_key: String, spawn_position = null) -> void:
	location_id = p_location_id
	loc = Game.data.locations[location_id]
	view = LocationView.new()
	add_child(view)
	view.setup(loc)
	_build_bounds()
	_build_obstacles()
	_build_interactables()

	player = PlayerScript.new()
	add_child(player)
	player.set_display_name(Game.state.player_name)
	var spawns: Dictionary = loc["spawns"]
	if spawn_position is Vector2:
		player.position = spawn_position
	else:
		player.position = Geo.vec(spawns.get(spawn_key, spawns["default"]))
	player.input_enabled = input_enabled
	_last_player_pos = player.position

	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	_update_camera()

	if loc.get("lighting", "day") == "evening":
		canvas_modulate = CanvasModulate.new()
		canvas_modulate.color = EVENING_TINT
		add_child(canvas_modulate)
	refresh_markers()
	Game.state_changed.connect(refresh_markers)


func is_evening() -> bool:
	return canvas_modulate != null


func _build_bounds() -> void:
	var size := Geo.vec(loc["size"])
	var inset := float(loc.get("bounds_inset", 20))
	var t := 200.0
	_add_rect_body(Rect2(-t, -t, size.x + t * 2, t + inset))
	_add_rect_body(Rect2(-t, size.y - inset, size.x + t * 2, t + inset))
	_add_rect_body(Rect2(-t, -t, t + inset, size.y + t * 2))
	_add_rect_body(Rect2(size.x - inset, -t, t + inset, size.y + t * 2))


func _build_obstacles() -> void:
	for b in loc.get("buildings", []):
		_add_rect_body(Geo.rect(b["rect"]))
	for d in loc.get("decor", []):
		if not d.get("solid", false):
			continue
		if d.has("rect"):
			_add_rect_body(Geo.rect(d["rect"]))
		elif d.has("pos"):
			_add_circle_body(Geo.vec(d["pos"]), float(d["r"]))


func _build_interactables() -> void:
	var uid := 0
	for placement in loc.get("npcs", []):
		var def: Dictionary = Game.data.npcs[placement["id"]]
		var node := NpcScript.new()
		node.position = Geo.vec(placement["pos"])
		add_child(node)
		node.setup(def)
		npc_nodes[def["id"]] = node
		uid += 1
		interactables.append({
			"uid": uid, "kind": "npc", "id": def["id"], "pos": node.position,
			"radius": float(placement.get("interact_radius", 64)),
			"prompt": "%s에게 말 걸기" % def["name"],
		})
	for b in loc.get("buildings", []):
		uid += 1
		interactables.append({
			"uid": uid, "kind": "door", "id": b["id"], "pos": Geo.vec(b["door"]), "radius": 56.0,
			"prompt": b.get("prompt", "들어가기"), "target": b["target"], "spawn": b["spawn"],
		})
	for e in loc.get("exits", []):
		uid += 1
		interactables.append({
			"uid": uid, "kind": "door", "id": e.get("id", "exit"), "pos": Geo.vec(e["pos"]), "radius": 56.0,
			"prompt": e.get("prompt", "나가기"), "target": e["target"], "spawn": e["spawn"],
		})
	for s in loc.get("signs", []):
		uid += 1
		interactables.append({
			"uid": uid, "kind": "sign", "id": s.get("id", "sign"), "pos": Geo.vec(s["pos"]), "radius": 56.0,
			"prompt": "%s 읽기" % s.get("title", "표지판"), "title": s.get("title", "표지판"), "text": s["text"],
		})
	for it in loc.get("interactables", []):
		uid += 1
		interactables.append({
			"uid": uid, "kind": it["kind"], "id": it["id"], "pos": Geo.vec(it["pos"]),
			"radius": float(it.get("radius", 60)), "prompt": it.get("prompt", ""),
		})


func _add_rect_body(r: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = r.get_center()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = r.size
	shape.shape = rect
	body.add_child(shape)
	add_child(body)


func _add_circle_body(center: Vector2, radius: float) -> void:
	var body := StaticBody2D.new()
	body.position = center
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	body.add_child(shape)
	add_child(body)


func _physics_process(_delta: float) -> void:
	if player == null or Game.state == null:
		return
	Game.state.player_position = player.position
	Game.state.has_player_position = true
	var moved := player.position.distance_to(_last_player_pos)
	if moved > 0.01:
		player_moved.emit(moved)
	_last_player_pos = player.position
	var best := {}
	var best_d := INF
	for it in interactables:
		var d: float = player.position.distance_to(it["pos"])
		if d <= it["radius"] and d < best_d:
			best = it
			best_d = d
	if best.get("uid", -1) != focused.get("uid", -1):
		focused = best
		focus_changed.emit(focused)


func _process(_delta: float) -> void:
	_update_camera()


func _update_camera() -> void:
	if camera == null or player == null:
		return
	var view_size := get_viewport_rect().size
	var size := Geo.vec(loc["size"])
	var target := player.position
	for axis in 2:
		if size[axis] <= view_size[axis]:
			target[axis] = size[axis] / 2.0
		else:
			target[axis] = clampf(target[axis], view_size[axis] / 2.0, size[axis] - view_size[axis] / 2.0)
	camera.position = target


func _unhandled_input(event: InputEvent) -> void:
	if input_enabled and event.is_action_pressed("interact"):
		if try_interact():
			get_viewport().set_input_as_handled()


## Interacts with the focused target (also used by the on-screen button). Returns true if something happened.
func try_interact() -> bool:
	if not input_enabled or focused.is_empty():
		return false
	interacted.emit(focused)
	return true


func find_interactable(kind: String, id: String) -> Dictionary:
	for it in interactables:
		if it["kind"] == kind and it["id"] == id:
			return it
	return {}


func refresh_markers() -> void:
	if Game.state == null:
		return
	for npc_id in npc_nodes:
		var entry := DialogueResolver.resolve(Game.data.dialogue, npc_id, location_id, Game.state)
		npc_nodes[npc_id].show_marker = entry.get("marker", false)


# --- home editing ------------------------------------------------------------

func set_edit_state(edit: bool, slot_id: String = "", item_id: String = "") -> void:
	view.set_edit_state(edit, slot_id, item_id)


func slot_at_mouse() -> String:
	return view.slot_at(get_global_mouse_position())
