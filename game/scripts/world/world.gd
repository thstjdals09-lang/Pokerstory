extends Node2D
## One playable location built from data/locations.json: drawing, collision, residents,
## doors, signs and other interactables, the player and the camera.
## Residents appear only where their placement matches the current time of day, and the
## whole location is tinted in the evening. Emits intents; Main decides what they do.

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
var _pickup_view: Node2D


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

	if Game.state.time_of_day == "evening":
		canvas_modulate = CanvasModulate.new()
		canvas_modulate.color = EVENING_TINT
		add_child(canvas_modulate)
	_pickup_view = PickupView.new()
	add_child(_pickup_view)
	sync_job_pickups()
	refresh_markers()
	Game.state_changed.connect(refresh_markers)
	Game.job_changed.connect(sync_job_pickups)


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
		if d.has("conditions") and not Conditions.check(d["conditions"], Game.state, location_id):
			continue
		if d.has("rect"):
			_add_rect_body(Geo.rect(d["rect"]))
		elif d.has("pos"):
			_add_circle_body(Geo.vec(d["pos"]), float(d["r"]))


func _build_interactables() -> void:
	var uid := 0
	# Residents come from their schedules: each stands in exactly one place per time of day.
	for npc_id in Game.data.npc_order:
		var place: Dictionary = Game.data.npc_place(npc_id, Game.state.time_of_day, Game.state)
		if place.get("loc", "") != location_id:
			continue
		var def: Dictionary = Game.data.npcs[npc_id]
		var node := NpcScript.new()
		node.position = Geo.vec(place["pos"])
		add_child(node)
		node.setup(def)
		node.set_activity(str(place.get("activity", "")))
		npc_nodes[npc_id] = node
		uid += 1
		interactables.append({
			"uid": uid, "kind": "npc", "id": npc_id, "pos": node.position,
			"radius": float(place.get("radius", 64)),
			"prompt": "%s에게 말 걸기" % def["name"],
		})
	var doors: Array = []
	doors.append_array(loc.get("buildings", []))
	doors.append_array(loc.get("gates", []))
	doors.append_array(loc.get("exits", []))
	for b in doors:
		uid += 1
		interactables.append({
			"uid": uid, "kind": "door", "id": b.get("id", "exit"),
			"pos": Geo.vec(b["door"] if b.has("door") else b["pos"]), "radius": 56.0,
			"prompt": b.get("prompt", "들어가기"), "target": b["target"], "spawn": b["spawn"],
			"requires_time": b.get("requires_time", ""), "closed_title": b.get("closed_title", ""),
			"closed_text": b.get("closed_text", ""), "wait_choice": b.get("wait_choice", ""),
			"unlock": b.get("unlock", {}), "locked_text": b.get("locked_text", "아직 들어갈 수 없어요."),
		})
	for s in loc.get("signs", []):
		uid += 1
		interactables.append({
			"uid": uid, "kind": "sign", "id": s.get("id", "sign"), "pos": Geo.vec(s["pos"]), "radius": 56.0,
			"prompt": "%s 읽기" % s.get("title", "표지판"), "title": s.get("title", "표지판"), "text": s["text"],
		})
	for it in loc.get("interactables", []):
		uid += 1
		var entry: Dictionary = it.duplicate()
		entry["uid"] = uid
		entry["pos"] = Geo.vec(it["pos"])
		entry["radius"] = float(it.get("radius", 60))
		interactables.append(entry)


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
		if it.has("conditions") and not Conditions.check(it["conditions"], Game.state, location_id):
			continue
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


## Rebuilds the odd-job pickup spots from Game.job (only in the job's location).
func sync_job_pickups() -> void:
	interactables = interactables.filter(func(it): return it["kind"] != "job_pickup")
	var shown := {}
	var run: PlazaJob = Game.job
	if run != null and Game.data.jobs[run.job_id].get("location", "") == location_id:
		for spot_id in run.remaining():
			var spot: Dictionary = run.spots[spot_id]
			shown[spot_id] = spot
			interactables.append({
				"uid": 1000 + int(str(spot_id).get_slice("_", 1)), "kind": "job_pickup", "id": spot_id,
				"pos": spot["pos"], "radius": 34.0,
				"prompt": {"card": "흩어진 카드 줍기", "chip": "흩어진 칩 줍기", "lantern": "등불 점검하기"}.get(str(spot["kind"]), "살펴보기"),
			})
	_pickup_view.spots = shown
	_pickup_view.queue_redraw()
	if focused.get("kind", "") == "job_pickup":
		focused = {}
		focus_changed.emit(focused)


func refresh_markers() -> void:
	if Game.state == null:
		return
	for npc_id in npc_nodes:
		npc_nodes[npc_id].show_marker = Game.npc_has_news(npc_id, location_id)


# --- home editing ------------------------------------------------------------

func set_edit_state(edit: bool, slot_id: String = "", item_id: String = "") -> void:
	view.set_edit_state(edit, slot_id, item_id)


func slot_at_mouse() -> String:
	return view.slot_at(get_global_mouse_position())


## Draws the scattered cards and chips of an odd-job run.
class PickupView extends Node2D:
	var spots := {}

	func _draw() -> void:
		for id in spots:
			var p: Vector2 = spots[id]["pos"]
			draw_circle(p + Vector2(0, 6), 12, Color(0, 0, 0, 0.18))
			if spots[id]["kind"] == "card":
				var card := Rect2(Vector2(-9, -12), Vector2(18, 24))
				draw_set_transform(p, 0.35, Vector2.ONE)
				draw_rect(card, Color("#fffdf8"))
				draw_rect(card, Color("#8a5a3c"), false, 2.0)
				draw_circle(Vector2.ZERO, 4, Color("#c0392b"))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			elif spots[id]["kind"] == "lantern":
				draw_circle(p, 16, Color(1, 0.85, 0.4, 0.3))
				draw_rect(Rect2(p + Vector2(-6, -10), Vector2(12, 16)), Color("#ffd27a"))
				draw_rect(Rect2(p + Vector2(-6, -10), Vector2(12, 16)), Color("#6b4a2f"), false, 2.0)
			else:
				draw_circle(p, 10, Color("#c8553d"))
				draw_circle(p, 10, Color("#fff3d6"), false, 2.5)
				draw_circle(p, 4, Color("#fff3d6"))
			draw_arc(p, 16, 0, TAU, 24, Color(1, 0.92, 0.5, 0.8), 2.0)
