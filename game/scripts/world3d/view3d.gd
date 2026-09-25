extends Node3D
## 3D view of the whole game (run_diorama.bat, started with -- --view3d).
## The 2D World keeps every rule (movement, collision, doors, talk, jobs, home editing); it is only
## hidden. This node redraws the current location from locations.json as simple blocks, 100 px = 1 m,
## x -> X and y -> Z, and mirrors the player, residents, signals, focus and job pickups each frame.
## Blocks only show what is where and how much room it takes; art replaces them later.
## Three levels of importance:
##   1  buildings, doors and gates, residents, the player: full height, strong colour, big labels
##   2  things you can use (boards, tables, bed, shelves, signs): a floating marker and a label
##   3  decoration (trees, flower beds, rugs, lamps): low and muted, no label
## Camera settings (distance, zoom, look-down angle, turn, blur, talk camera) come from the diorama
## scene (diorama/diorama.tscn, the Diorama node's Inspector in edit_diorama.bat), read at start.
## Camera: follows the player with a little look-ahead; in a talk with a resident it glides to a side
## view of the pair; walking into a door pushes toward it, and a new place settles in from further out.
## Layout: "angle3d" (degrees) on a building or decor turns it in 3D only (buildings around their
## door, so the 2D rules stay the same); each place's idea is in its "view3d.concept".

const PX := 0.01
const FONT := preload("res://assets/fonts/ui_font.tres")
const WALL_H := 2.4

var main: Node
var _world: Node2D
var _dirty := false
var _root: Node3D
var _player: Node3D
var _player_body: Node3D
var _npcs := {}
var _signals := {}
var _focus: MeshInstance3D
var _pickups: Node3D
var _pickup_key := ""
var _slots: Node3D
var _slot_key := ""
var _cam: Camera3D
var _env: Environment
var _sun: DirectionalLight3D
var _night: Array = []
var _glows: Array = []
var _t := 0.0
var _doors := {}
var _follow_xf := Transform3D()
var _follow_ready := false
var _last_pos := Vector3.ZERO
var _look := Vector3.ZERO
var _arrive := 0.0
var _door_at := Vector3.ZERO
var _door_push := 0.0
var _talk_t := 0.0
var _talk_xf := Transform3D()
var _talk_npc := ""
## From diorama.tscn (see _load_camera_settings); these are the fallbacks.
var cam_dist := 28.74
var cam_fov := 20.0
var cam_pitch := 22.0
var cam_yaw := 0.0
var blur_on := true
var blur_amount := 0.07
var blur_near_start := 5.0
var blur_far_start := 6.0
var blur_softness := 5.0
var talk_distance := 9.0
var talk_fov := 30.0
var talk_pitch := 17.0
var talk_side := 0.75
var talk_lift := 0.85
## Rooms are smaller than the square: the camera comes this much closer indoors.
const INTERIOR_ZOOM := 0.8
var _labels: Array = []
var _talk_hidden: Array = []
## Glide time into a talk; --instant-camera (screenshots in tests) makes it near instant.
var talk_glide := 0.8
var _instant := false


func _ready() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.ssao_enabled = true
	_env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 40.0
	_sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(_sun)
	_load_camera_settings()
	_cam = Camera3D.new()
	_cam.fov = cam_fov
	_cam.attributes = CameraAttributesPractical.new()
	add_child(_cam)
	_cam.current = true
	_cam.position = Vector3(8, 12, 18)
	_focus = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	_focus.mesh = torus
	var fm := _mat(Color("#ffd23f"))
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_focus.material_override = fm
	add_child(_focus)
	Game.state_changed.connect(func(): _dirty = true)
	if "--instant-camera" in OS.get_cmdline_user_args():
		talk_glide = 0.02
		_instant = true


## Reads the camera, blur and talk-camera values saved in the diorama scene without building it:
## values the scene overrides come from its SceneState, the rest are the script's defaults.
func _load_camera_settings() -> void:
	var script: Script = load("res://diorama/diorama.gd")
	var names := {"cam_distance": "cam_dist", "cam_fov": "cam_fov", "cam_pitch": "cam_pitch", "cam_yaw": "cam_yaw",
		"blur_on": "blur_on", "blur_amount": "blur_amount", "blur_near_start": "blur_near_start",
		"blur_far_start": "blur_far_start", "blur_softness": "blur_softness", "talk_distance": "talk_distance",
		"talk_fov": "talk_fov", "talk_pitch": "talk_pitch", "talk_side": "talk_side", "talk_lift": "talk_lift",
		"talk_glide": "talk_glide"}
	if script != null:
		for from in names:
			var v = script.get_property_default_value(from)
			if v != null:
				set(names[from], v)
	var packed: PackedScene = load("res://diorama/diorama.tscn")
	if packed == null:
		return
	var st := packed.get_state()
	for i in st.get_node_property_count(0):
		var n := str(st.get_node_property_name(0, i))
		if names.has(n):
			set(names[n], st.get_node_property_value(0, i))


func _apply_blur(dist: float) -> void:
	var a: CameraAttributesPractical = _cam.attributes
	a.dof_blur_far_enabled = blur_on
	a.dof_blur_near_enabled = blur_on
	a.dof_blur_amount = blur_amount
	a.dof_blur_far_distance = dist + blur_far_start
	a.dof_blur_near_distance = maxf(0.1, dist - blur_near_start)
	a.dof_blur_far_transition = blur_softness
	a.dof_blur_near_transition = blur_softness


func _process(delta: float) -> void:
	_t += delta
	var w: Node2D = main.world if main != null else null
	if w != _world or (_dirty and w != null):
		if w != _world:
			# a new place settles in from a little further out
			_arrive = 0.0 if _instant else 1.0
			_door_push = 0.0
			_talk_t = 0.0
			_talk_npc = ""
			_follow_ready = false
		_dirty = false
		_world = w
		_rebuild()
	if w == null or not is_instance_valid(w):
		_focus.visible = false
		return
	_sync(delta)


# --- building a location ---------------------------------------------------------------------------

func _rebuild() -> void:
	if _root != null:
		_root.queue_free()
	_root = Node3D.new()
	add_child(_root)
	_npcs.clear()
	_signals.clear()
	_doors.clear()
	_labels.clear()
	_talk_hidden.clear()
	_night.clear()
	_glows.clear()
	_pickup_key = ""
	_slot_key = ""
	_pickups = null
	_slots = null
	if _world == null or not is_instance_valid(_world):
		return
	# Everything the 2D world draws on its own layers stays hidden (fireflies, overlays).
	for c in _world.find_children("*", "CanvasLayer", true, false):
		c.visible = false
	var loc: Dictionary = _world.loc
	var id: String = _world.location_id
	var evening: bool = Game.state.time_of_day == "evening"
	if loc.get("interior", false):
		_interior(loc)
	else:
		_exterior(loc)
	for b in loc.get("buildings", []):
		_building(b, id)
	for g in loc.get("gates", []):
		_gate(g)
	for e in loc.get("exits", []):
		_exit(e)
	for s in loc.get("signs", []):
		_sign(s)
	for d in loc.get("decor", []):
		if _shown(d, id):
			_decor(d)
	for it in loc.get("interactables", []):
		if _shown(it, id):
			_usable(it)
	_player = Node3D.new()
	_root.add_child(_player)
	_player_body = _figure(_player, Color("#3a7bd5"), Color("#f6d7bd"), 1.05)
	_box(_player_body, Vector3(0.1, 0.1, 0.18), Vector3(0, 0.95, 0.24), _mat(Color.WHITE))
	for npc_id in _world.npc_nodes:
		var node: Node2D = _world.npc_nodes[npc_id]
		var def: Dictionary = Game.data.npcs[npc_id]
		var look: Dictionary = def.get("look", {})
		var n := Node3D.new()
		n.position = _v(node.position)
		_root.add_child(n)
		var h := 0.75 if str(look.get("shape", "")) in ["fairy", "stone"] else 1.0
		_figure(n, Color(str(look.get("color", "#cccccc"))), Color(str(look.get("accent", "#ffffff"))), h)
		_label(n, str(def["name"]), Vector3(0, h + 0.35, 0), 30, Color.WHITE)
		var sig := _label(n, "", Vector3(0, h + 0.8, 0), 64, Color("#ffd23f"))
		_npcs[npc_id] = n
		_signals[npc_id] = sig
	_apply_time(evening)
	if loc.get("interior", false):
		# indoors: the room light matters, not the sun
		_sun.light_energy *= 0.35
		_env.ambient_light_energy = 0.6


func _exterior(loc: Dictionary) -> void:
	var size := _v(Geo.vec(loc["size"]))
	var ground := Color(str(loc.get("ground", "#a3c982")))
	# Outside the walkable area: the same ground, darker.
	_box(_root, Vector3(size.x + 40, 0.1, size.z + 40), Vector3(size.x / 2, -0.06, size.z / 2), _mat(ground.darkened(0.45)))
	_box(_root, Vector3(size.x, 0.1, size.z), Vector3(size.x / 2, -0.05, size.z / 2), _mat(ground))
	var path := _mat(Color(str(loc.get("path_color", "#e6d3a3"))))
	for p in loc.get("paths", []):
		var r := Geo.rect(p)
		_flat(r, 0.01, path)
	for pl in loc.get("plazas", []):
		_cyl(_root, float(pl["radius"]) * PX, 0.02, _v(Geo.vec(pl["center"])) + Vector3(0, 0.01, 0), _mat(Color(str(pl.get("color", "#ecdcb4")))))


func _interior(loc: Dictionary) -> void:
	var size := _v(Geo.vec(loc["size"]))
	var inset := float(loc.get("bounds_inset", 28)) * PX
	var wall := _mat(Color(str(loc.get("wall", "#8b6a50"))))
	_box(_root, Vector3(size.x + 40, 0.1, size.z + 40), Vector3(size.x / 2, -0.08, size.z / 2), _mat(Color("#2a211c")))
	_box(_root, Vector3(size.x, 0.1, size.z), Vector3(size.x / 2, -0.05, size.z / 2), _mat(Color(str(loc.get("floor", "#dcbf94")))))
	# back wall tall, side walls lower, front wall a kerb so the camera sees in
	_box(_root, Vector3(size.x, 2.4, inset), Vector3(size.x / 2, 1.2, inset / 2), wall)
	for x in [inset / 2, size.x - inset / 2]:
		_box(_root, Vector3(inset, 1.2, size.z), Vector3(x, 0.6, size.z / 2), wall)
	_box(_root, Vector3(size.x, 0.25, inset), Vector3(size.x / 2, 0.125, size.z - inset / 2), wall)
	var light := OmniLight3D.new()
	light.position = Vector3(size.x / 2, 2.2, size.z / 2)
	light.omni_range = maxf(size.x, size.z)
	light.light_energy = 1.6 if Game.state.time_of_day == "evening" else 1.0
	light.light_color = Color("#ffd9a8")
	_root.add_child(light)


func _building(b: Dictionary, loc_id: String) -> void:
	var r := Geo.rect(b["rect"])
	var door_px := Geo.vec(b["door"])
	# everything is built relative to the door on the front edge, then turned around it
	var pivot := Node3D.new()
	pivot.position = Vector3(door_px.x * PX, 0, r.end.y * PX)
	pivot.rotation.y = deg_to_rad(float(b.get("angle3d", 0.0)))
	_root.add_child(pivot)
	var fp := Rect2((r.position - Vector2(door_px.x, r.end.y)) * PX, r.size * PX)
	var centre := Vector3(fp.get_center().x, 0, fp.get_center().y)
	var parent := pivot
	var wall := _mat(Color(str(b.get("wall", "#efe0c8"))))
	var roof := _mat(Color(str(b.get("roof", "#9a7a6a"))))
	_box(parent, Vector3(fp.size.x, WALL_H, fp.size.y), centre + Vector3(0, WALL_H / 2, 0), wall)
	var prism := PrismMesh.new()
	prism.size = Vector3(fp.size.y + 0.3, 1.2, fp.size.x + 0.3)
	var ri := MeshInstance3D.new()
	ri.mesh = prism
	ri.material_override = roof
	ri.position = centre + Vector3(0, WALL_H + 0.6, 0)
	ri.rotation.y = PI / 2
	parent.add_child(ri)
	var door := Vector3.ZERO
	var open: bool = Conditions.check(b.get("unlock", {}), Game.state, loc_id)
	var door_mat := _door_mat(Color("#6b3f24") if open else Color("#4a4440"))
	_doors[str(b["id"])] = door_mat
	_box(parent, Vector3(0.9, 1.5, 0.08), Vector3(door.x, 0.75, fp.end.y + 0.04), door_mat)
	# two warm windows on the front, lit in the evening
	var win := _glow(Color("#ffd27a"))
	for wx in [fp.position.x + fp.size.x * 0.2, fp.end.x - fp.size.x * 0.2]:
		if absf(wx - door.x) > 0.7:
			_box(parent, Vector3(0.6, 0.6, 0.06), Vector3(wx, 1.4, fp.end.y + 0.03), win)
	_label(parent, str(b.get("label", b.get("prompt", ""))), centre + Vector3(0, WALL_H + 1.6, fp.size.y / 2), 56, Color.WHITE)


func _gate(g: Dictionary) -> void:
	var p := _v(Geo.vec(g["pos"]))
	var wood := _door_mat(Color("#7a5230"))
	_doors[str(g["id"])] = wood
	for x in [-0.6, 0.6]:
		_box(_root, Vector3(0.18, 2.2, 0.18), p + Vector3(x, 1.1, 0), wood)
	_box(_root, Vector3(1.6, 0.2, 0.22), p + Vector3(0, 2.2, 0), wood)
	_label(_root, str(g.get("label", "")), p + Vector3(0, 2.8, 0), 48, Color("#fff3d6"))


func _exit(e: Dictionary) -> void:
	var p := _v(Geo.vec(e["pos"]))
	var mat := _door_mat(Color("#6b4a32"))
	_doors[str(e["id"])] = mat
	_box(_root, Vector3(1.0, 0.04, 0.5), p + Vector3(0, 0.02, 0), mat)
	_label(_root, "↓ " + str(e.get("prompt", "나가기")), p + Vector3(0, 0.9, 0), 40, Color("#fff3d6"))


func _sign(s: Dictionary) -> void:
	var p := _v(Geo.vec(s["pos"]))
	var wood := _mat(Color("#8a5a36"))
	_box(_root, Vector3(0.1, 1.2, 0.1), p + Vector3(0, 0.6, 0), wood)
	_box(_root, Vector3(0.8, 0.4, 0.06), p + Vector3(0, 1.1, 0), wood)
	_label(_root, str(s.get("title", "표지판")), p + Vector3(0, 1.7, 0), 34, Color("#fff3d6"))


## Level 2: something the player can use. A floating diamond over it and its name.
func _usable(it: Dictionary) -> void:
	var p := _v(Geo.vec(it["pos"]))
	var col: Color = {"poker_table": Color("#2f9a62"), "job_board": Color("#e8894a"), "home_edit": Color("#4a8fd5"),
		"rest": Color("#7a6ad5")}.get(str(it.get("kind", "")), Color("#e0b43a"))
	match str(it.get("shape", "")):
		"table":
			_cyl(_root, 0.55, 0.75, p + Vector3(0, 0.375, 0), _mat(Color("#6b4a30")))
		"sign":
			_box(_root, Vector3(0.7, 0.9, 0.08), p + Vector3(0, 0.45, 0), _mat(Color("#8a5a36")))
	var gem := _box(_root, Vector3(0.22, 0.22, 0.22), p + Vector3(0, 1.5, 0), _glow(col))
	gem.rotation = Vector3(PI / 4, PI / 4, 0)
	var title_text := str(it.get("title", it.get("prompt", "")))
	_label(_root, title_text, p + Vector3(0, 1.95, 0), 32, col.lightened(0.5))


## Level 3: decoration, low and muted.
func _decor(d: Dictionary) -> void:
	var before := _root.get_child_count()
	_decor_shape(d)
	var turn := deg_to_rad(float(d.get("angle3d", 0.0)))
	if turn != 0.0:
		for i in range(before, _root.get_child_count()):
			var c = _root.get_child(i)
			if c is Node3D:
				c.rotation.y += turn


func _decor_shape(d: Dictionary) -> void:
	var type := str(d.get("type", ""))
	if d.has("rect"):
		var r := Geo.rect(d["rect"])
		var col := Color(str(d.get("color", "#a9784f")))
		match type:
			"house":
				_box(_root, Vector3(r.size.x * PX, 2.0, r.size.y * PX), _v(r.get_center()) + Vector3(0, 1.0, 0), _mat(Color("#d9cbb4")))
			"water":
				_flat(r, 0.005, _mat(Color("#5fa8c8"), 0.1))
			"rug":
				_flat(r, 0.012, _mat(Color(str(d.get("color", "#c97b63")))))
			"flowers", "garden":
				_flat(r, 0.25, _mat(Color("#7aa65a")))
			"deck", "nook":
				_flat(r, 0.12, _mat(Color("#a8845a")))
			"stall":
				_flat(r, 1.0, _mat(Color("#c9a37a")))
			"window", "awning", "garland":
				return
			_:
				_flat(r, 0.6 if d.get("solid", false) else 0.05, _mat(col.lerp(Color("#9c8a78"), 0.3)))
		return
	var p := _v(Geo.vec(d.get("art_pos", d.get("pos", [0, 0]))))
	var rad := float(d.get("r", 16)) * PX
	var key := str(d.get("art", ""))
	if type == "tree" or key.contains("tree"):
		_cyl(_root, 0.1, 1.0, p + Vector3(0, 0.5, 0), _mat(Color("#6b4a30")))
		_ball(_root, maxf(rad, 0.35) * 1.3, p + Vector3(0, 1.4, 0), _mat(Color("#f0b3c4") if key.contains("blossom") else Color("#5f8f45")))
	elif type == "fountain":
		_cyl(_root, rad, 0.5, p + Vector3(0, 0.25, 0), _mat(Color("#b9ad9a")))
		_cyl(_root, rad * 0.85, 0.52, p + Vector3(0, 0.26, 0), _mat(Color("#7fc4e0"), 0.1))
		_cyl(_root, 0.12, 1.4, p + Vector3(0, 0.7, 0), _mat(Color("#b9ad9a")))
	elif type == "felt_table":
		_cyl(_root, rad, 0.75, p + Vector3(0, 0.375, 0), _mat(Color("#2f7a52")))
	elif type in ["lantern", "lantern_row"] or key.contains("lamp"):
		_cyl(_root, 0.05, 1.6, p + Vector3(0, 0.8, 0), _mat(Color("#2a2522")))
		_box(_root, Vector3(0.2, 0.25, 0.2), p + Vector3(0, 1.7, 0), _glow(Color("#ffc46b")))
		_lamp_light(p + Vector3(0, 1.7, 0), 3.0)
	elif type in ["glow", "circle"]:
		return
	elif key.contains("bush") or key.contains("pot") or key.contains("planter"):
		_ball(_root, maxf(rad, 0.2), p + Vector3(0, maxf(rad, 0.2) * 0.8, 0), _mat(Color("#5f8a3c")))
	else:
		# boards, booths, benches, crates, postboxes: a small box of their footprint
		var s := maxf(rad * 2.0, 0.4)
		_box(_root, Vector3(s, 0.6, s * 0.6), p + Vector3(0, 0.3, 0), _mat(Color("#9c7a55")))


# --- every frame -----------------------------------------------------------------------------------

func _sync(delta: float) -> void:
	var p: Node2D = _world.player
	var pos := _v(p.position)
	var vel := (pos - _last_pos) / maxf(delta, 0.001) if _follow_ready else Vector3.ZERO
	_last_pos = pos
	var moving := vel.length() > 0.4
	_player.position = pos
	# a small hop while walking, smooth turns
	_player_body.position.y = absf(sin(_t * 11.0)) * 0.07 if moving else lerpf(_player_body.position.y, 0.0, 0.3)
	var f: Vector2 = p.facing
	var face := atan2(f.x, f.y)
	var mode := str(main.ui_mode)
	var npc_id := str(main._dialogue_npc) if mode == "dialogue" else ""
	if _npcs.has(npc_id):
		face = atan2(_npcs[npc_id].position.x - pos.x, _npcs[npc_id].position.z - pos.z)
	_player_body.rotation.y = lerp_angle(_player_body.rotation.y, face, 0.25)
	var signals: Dictionary = Game.world_signals()
	for id in _npcs:
		var kind := str(signals.get(id, ""))
		var lab: Label3D = _signals[id]
		lab.text = {"main": "!", "story": "…", "request": "!"}.get(kind, "")
		lab.modulate = Color.WHITE if kind == "story" else Color("#ffd23f")
		lab.font_size = 40 if kind == "request" else 72
		lab.position.y = (1.8 if kind == "request" else 1.9) + sin(_t * 4.0) * 0.06
		# the resident in the talk turns to the player
		var body: Node3D = _npcs[id].get_child(0)
		var want_turn := atan2(pos.x - _npcs[id].position.x, pos.z - _npcs[id].position.z) if id == npc_id else 0.0
		body.rotation.y = lerp_angle(body.rotation.y, want_turn, 0.2)
	var focused: Dictionary = _world.focused
	_focus.visible = not focused.is_empty() and mode == "world"
	if not focused.is_empty():
		_focus.position = _v(focused["pos"]) + Vector3(0, 0.03, 0)
	for id in _doors:
		var lit: bool = focused.get("kind", "") == "door" and str(focused.get("id", "")) == id
		_doors[id].emission_energy_multiplier = lerpf(_doors[id].emission_energy_multiplier, (0.6 + sin(_t * 5.0) * 0.2) if lit else 0.0, 0.3)
	if focused.get("kind", "") == "door":
		_door_at = _v(focused["pos"])
	_sync_pickups()
	_sync_slots()
	_camera(delta, pos, vel, mode, npc_id)


func _camera(delta: float, pos: Vector3, vel: Vector3, mode: String, npc_id: String) -> void:
	var interior: bool = _world.loc.get("interior", false)
	# look a little ahead of where the player walks
	var ahead := Vector3(vel.x, 0, vel.z) * 0.35
	if ahead.length() > 1.4:
		ahead = ahead.normalized() * 1.4
	_look = _look.lerp(ahead, clampf(delta * 2.5, 0.0, 1.0))
	# walking into a door: push toward it while the screen fades
	_door_push = move_toward(_door_push, 1.0 if mode == "transition" else 0.0, delta / 0.35)
	_arrive = move_toward(_arrive, 0.0, delta / 1.1)
	var focus := (pos + _look).lerp(_door_at, _door_push * 0.6)
	var pitch := deg_to_rad(cam_pitch)
	var base_dist := cam_dist * (INTERIOR_ZOOM if interior else 1.0)
	var dist := base_dist * (1.0 - 0.3 * _door_push) * (1.0 + 0.35 * smoothstep(0.0, 1.0, _arrive))
	var back := Vector3(0, sin(pitch), cos(pitch)).rotated(Vector3.UP, deg_to_rad(cam_yaw))
	var want := Transform3D(Basis(), focus + back * dist).looking_at(focus, Vector3.UP)
	if not _follow_ready:
		_follow_xf = want
		_follow_ready = true
	var k := clampf(delta * 5.0, 0.0, 1.0)
	_follow_xf = Transform3D(_follow_xf.basis.slerp(want.basis, k), _follow_xf.origin.lerp(want.origin, k))
	# talk: glide to a side view of the pair
	if _npcs.has(npc_id) and npc_id != _talk_npc:
		_talk_npc = npc_id
		_talk_xf = _talk_shot(pos, _npcs[npc_id].position, interior)
		_hide_blockers(_talk_xf.origin, (pos + _npcs[npc_id].position) / 2.0 + Vector3(0, 0.5, 0))
	if not _npcs.has(npc_id) and _talk_t == 0.0 and _talk_npc != "":
		_talk_npc = ""
		for n in _talk_hidden:
			if is_instance_valid(n):
				n.visible = true
		_talk_hidden.clear()
	for l in _labels:
		if is_instance_valid(l):
			l.visible = _talk_t < 0.3
	_talk_t = move_toward(_talk_t, 1.0 if _npcs.has(npc_id) else 0.0, delta / talk_glide)
	var t := smoothstep(0.0, 1.0, _talk_t)
	_cam.transform = _follow_xf.interpolate_with(_talk_xf, t) if t > 0.0 else _follow_xf
	_cam.fov = lerpf(cam_fov, talk_fov, t)
	_apply_blur(lerpf(base_dist, talk_distance, t))


## Side view of the player and the resident, from the side of their line that looks across the
## place, leaning toward the usual camera side. Spots inside a building, behind one, or outside the
## room are skipped; it tries the other side, less turn and shorter distances before giving up.
func _talk_shot(p: Vector3, n: Vector3, interior: bool) -> Transform3D:
	var mid := (p + n) / 2.0
	var axis := Vector3(n.x - p.x, 0, n.z - p.z)
	if axis.length() < 0.05:
		axis = Vector3.RIGHT
	axis = axis.normalized()
	var perp := Vector3(-axis.z, 0, axis.x)
	var size := _v(Geo.vec(_world.loc["size"]))
	var to_centre := Vector3(size.x / 2.0 - mid.x, 0, size.z / 2.0 - mid.z)
	# first choice: the side away from the centre (looking across the place), south side on a tie
	if perp.dot(to_centre) - perp.z * 2.0 > 0.0:
		perp = -perp
	var aim := mid + Vector3(0, 0.6 - talk_lift, 0)
	var pitch := deg_to_rad(talk_pitch)
	var near := talk_distance * (INTERIOR_ZOOM * 0.75 if interior else 1.0)
	for side_sign in [1.0, -1.0]:
		for turn in [talk_side, talk_side * 0.66, talk_side * 0.33]:
			for dist in [near, near * 0.8, near * 0.6]:
				var flat: Vector3 = (Vector3(0, 0, 1) * (1.0 - turn) + perp * side_sign * turn).normalized()
				var eye: Vector3 = mid + (flat * cos(pitch) + Vector3.UP * sin(pitch)) * dist + Vector3(0, 0.6, 0)
				if _clear_view(eye, mid, interior, size):
					return Transform3D(Basis(), eye).looking_at(aim, Vector3.UP)
	# nothing clear: a closer version of the usual view
	var eye2 := mid + Vector3(0, sin(deg_to_rad(40.0)), cos(deg_to_rad(40.0))) * 6.0
	return Transform3D(Basis(), eye2).looking_at(aim, Vector3.UP)


## The camera spot is not inside or behind a building, and indoors it stays within the room.
func _clear_view(eye: Vector3, mid: Vector3, interior: bool, size: Vector3) -> bool:
	var e := Vector2(eye.x, eye.z)
	var m := Vector2(mid.x, mid.z)
	if interior:
		var inset := float(_world.loc.get("bounds_inset", 28)) * PX
		return e.x > inset + 0.2 and e.x < size.x - inset - 0.2 and e.y > inset + 0.2 and e.y < size.z + 1.5
	var blocks: Array = []
	for b in _world.loc.get("buildings", []):
		blocks.append(b["rect"])
	for d in _world.loc.get("decor", []):
		if str(d.get("type", "")) == "house":
			blocks.append(d["rect"])
	for r in blocks:
		var rr := Rect2(Geo.rect(r).position * PX, Geo.rect(r).size * PX).grow(0.3)
		if rr.has_point(e):
			return false
		for i in 11:
			if rr.has_point(e.lerp(m, i / 10.0)):
				return false
	return true


## Hides what stands between the talk camera and the pair (trees, lamps, boards) until the talk ends.
func _hide_blockers(eye: Vector3, target: Vector3) -> void:
	var seg := target - eye
	var len2 := seg.length_squared()
	for c in _root.get_children():
		if not (c is Node3D) or c == _player or _npcs.values().has(c) or not c.visible:
			continue
		var n3: Node3D = c
		var at := n3.global_position
		var aabb_size := 1.0
		if c is MeshInstance3D:
			var ab: AABB = c.get_aabb()
			if ab.size.x > 6.0 or ab.size.z > 6.0:
				continue  # ground, floors, walls
			at = c.global_transform * ab.get_center()
			aabb_size = ab.size.length()
		var t := clampf((at - eye).dot(seg) / len2, 0.0, 1.0)
		if t > 0.92:
			continue
		if at.distance_to(eye + seg * t) < 0.6 + aabb_size * 0.35:
			c.visible = false
			_talk_hidden.append(c)


func _sync_pickups() -> void:
	var spots: Array = _world.interactables.filter(func(it): return it["kind"] == "job_pickup")
	var key := ",".join(spots.map(func(it): return str(it["id"])))
	if key == _pickup_key:
		return
	_pickup_key = key
	if _pickups != null:
		_pickups.queue_free()
	_pickups = Node3D.new()
	_root.add_child(_pickups)
	for it in spots:
		var b := _box(_pickups, Vector3(0.25, 0.08, 0.35), _v(it["pos"]) + Vector3(0, 0.05, 0), _glow(Color("#ffe066")))
		b.rotation.y = 0.5


func _sync_slots() -> void:
	var loc: Dictionary = _world.loc
	if not loc.has("slots"):
		return
	var view = _world.view
	var edit: bool = view.edit_mode
	var parts: Array = [edit, view.selected_slot, view.preview_item]
	for s in loc["slots"]:
		parts.append(Game.state.placement_at(s["id"]))
	var key := str(parts)
	if key == _slot_key:
		return
	_slot_key = key
	if _slots != null:
		_slots.queue_free()
	_slots = Node3D.new()
	_root.add_child(_slots)
	var evening: bool = Game.state.time_of_day == "evening"
	for s in Game.home_slots(_world.location_id):
		var r := Geo.rect(s["rect"])
		var c := _v(r.get_center())
		var placed: String = Game.state.placement_at(s["id"])
		if edit:
			var sel: bool = s["id"] == view.selected_slot
			var m := _mat(Color(1, 0.85, 0.3, 0.55 if sel else 0.2))
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_box(_slots, Vector3(r.size.x * PX, 0.02, r.size.y * PX), c + Vector3(0, 0.02, 0), m)
		var item: String = placed if placed != "" else (str(view.preview_item) if edit and s["id"] == view.selected_slot else "")
		if item != "":
			var col := Game.item_color(item, Color("#c9a37a"))
			_box(_slots, Vector3(0.45, 0.5, 0.45), c + Vector3(0, 0.25, 0), _mat(col))
			if placed.contains("lamp"):
				# a placed lamp lights the room, softly by day
				var l := OmniLight3D.new()
				l.position = c + Vector3(0, 0.9, 0)
				l.omni_range = 5.0
				l.light_energy = 1.6 if evening else 0.7
				l.light_color = Color("#ffb863")
				_slots.add_child(l)


func _apply_time(evening: bool) -> void:
	var sm: ProceduralSkyMaterial = _env.sky.sky_material
	if evening:
		_sun.light_color = Color("#8090d8")
		_sun.light_energy = 0.25
		sm.sky_top_color = Color("#1b2550")
		sm.sky_horizon_color = Color("#3a3f78")
		_env.ambient_light_energy = 0.45
	else:
		_sun.light_color = Color("#fff0d8")
		_sun.light_energy = 1.1
		sm.sky_top_color = Color("#8fb6e8")
		sm.sky_horizon_color = Color("#f2dcb8")
		_env.ambient_light_energy = 0.7
	for l in _night:
		if is_instance_valid(l):
			l.visible = evening
	for g in _glows:
		g.emission_energy_multiplier = 1.6 if evening else 0.3


# --- small helpers ---------------------------------------------------------------------------------

func _v(p: Vector2) -> Vector3:
	return Vector3(p.x * PX, 0.0, p.y * PX)


func _shown(d: Dictionary, loc_id: String) -> bool:
	return not d.has("conditions") or Conditions.check(d["conditions"], Game.state, loc_id)


func _mat(c: Color, rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## A door material that lights up when the door is the focused target.
func _door_mat(c: Color) -> StandardMaterial3D:
	var m := _mat(c)
	m.emission_enabled = true
	m.emission = Color("#ffcf5a")
	m.emission_energy_multiplier = 0.0
	return m


func _glow(c: Color) -> StandardMaterial3D:
	var m := _mat(c, 0.5)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.3
	_glows.append(m)
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _flat(r: Rect2, h: float, m: Material) -> MeshInstance3D:
	return _box(_root, Vector3(r.size.x * PX, h, r.size.y * PX), _v(r.get_center()) + Vector3(0, h / 2.0, 0), m)


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _ball(parent: Node3D, r: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## A standing figure: body, head, and a thin shadow disc.
func _figure(parent: Node3D, body: Color, head: Color, h: float) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	_cyl(n, 0.22, h * 0.6, Vector3(0, h * 0.3, 0), _mat(body))
	_ball(n, 0.2, Vector3(0, h * 0.6 + 0.18, 0), _mat(head))
	return n


func _lamp_light(pos: Vector3, reach: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.omni_range = reach
	l.light_energy = 1.2
	l.light_color = Color("#ffb863")
	l.visible = false
	_root.add_child(l)
	_night.append(l)
	return l


func _label(parent: Node3D, text: String, pos: Vector3, size: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = FONT
	l.font_size = size
	l.pixel_size = 0.009
	l.outline_size = 10
	l.outline_modulate = Color(0.1, 0.07, 0.05, 0.9)
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	parent.add_child(l)
	_labels.append(l)
	return l
