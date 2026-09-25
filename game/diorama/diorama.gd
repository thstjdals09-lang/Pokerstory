extends Node3D
## 3D diorama prototype of the village square, built only from primitive shapes (no image assets).
## Composition pass: the square is re-laid out for the camera (fountain in the middle, buildings
## around it, props filling the space, paths to every door, trees and fences framing the edges).
## The same buildings, doors and gates as the game data (locations.json) keep their links; only the
## 3D placement differs. Metres; the camera looks from +Z. Run with run_diorama.bat (Forward+).
## Keys: WASD / arrows walk, T day <-> evening, F1 edit mode, Esc quit.
## Edit mode (F1): sliders for the camera and the selected building. Click a building to select it,
## drag it on the ground, Q / E turn it; mouse wheel zooms, right-drag orbits, middle-drag pans.
## "저장" writes diorama/layout.json, which is loaded on the next start.
## Screenshot mode: -- --shot=<png> [--evening] quits after saving one frame.

const PX := 0.01
const WALK := 3.2

var _evening := false
var _env: Environment
var _sun: DirectionalLight3D
var _night_lights: Array = []
var _glows: Array = []  # [material, day energy, evening energy]
var _player: CharacterBody3D
var _player_body: Node3D
var _cam: Camera3D
var _bobbers: Array = []  # [node, base y, speed, amount]
var _t := 0.0
var _hud_loc: Label
var _hud_icon: TextureRect
var _prompt: Control
var _lumi: Node3D
var _shot := ""
const LAYOUT_FILE := "res://diorama/layout.json"
## Editable camera (edit mode sliders; saved to layout.json).
## Defaults are the owner's saved layout (2026-09-25).
const CAM_DEFAULT := {"dist": 11.53, "pitch": 20.6, "fov": 53.5, "yaw": 0.0, "cx": 0.00, "cz": -3.20, "lean_x": 0.55, "lean_z": 0.55}
var cam := CAM_DEFAULT.duplicate()
var _buildings: Array = []
var _building_roots: Array = []
var _pave_root: Node3D
var _pave_dirty := 0.0
var _edit := false
var _edit_panel: PanelContainer
var _sel := 0
var _sel_label: Label
var _sliders := {}
var _dragging := ""
var _drag_from := Vector2.ZERO
var _sel_ring: MeshInstance3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.get_slice("=", 1)
		if a == "--evening":
			_evening = true
	_buildings = BUILDINGS.duplicate(true)
	_load_layout()
	_build_world_env()
	_build_ground()
	for i in _buildings.size():
		_building_roots.append(_build_building(_buildings[i]))
	_build_decor()
	_build_people()
	_build_camera()
	_build_hud()
	_build_editor()
	_apply_time()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--player="):
			var xz := a.get_slice("=", 1).split(",")
			_player.position = Vector3(float(xz[0]), 0, float(xz[1]))
			_follow(1.0)
		if a.begins_with("--persp="):
			_set_perspective(float(a.get_slice("=", 1)))
			_follow(1.0)
	if "--edit" in OS.get_cmdline_user_args():
		_set_edit(true)
	if _shot != "":
		_take_shot.call_deferred()


func _v(p: Array) -> Vector3:
	return Vector3(float(p[0]) * PX, 0.0, float(p[1]) * PX)


# --- materials and shapes ----------------------------------------------------------------------

func _mat(color: Color, rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _glow_mat(color: Color, day: float, evening: float) -> StandardMaterial3D:
	var m := _mat(color, 0.6)
	m.emission_enabled = true
	m.emission = color
	_glows.append([m, day, evening])
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, seg: int = 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = seg
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _ball(parent: Node3D, r: float, pos: Vector3, mat: Material, squash: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.scale = squash
	parent.add_child(mi)
	return mi


func _prism(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)
	return mi


func _solid_box(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = center
	add_child(body)


func _solid_round(center: Vector3, r: float) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = 2.0
	cs.shape = shape
	body.add_child(cs)
	body.position = center + Vector3(0, 1, 0)
	add_child(body)


# --- light and camera ---------------------------------------------------------------------------

func _build_world_env() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.ssao_enabled = true
	_env.ssao_radius = 1.2
	_env.ssao_intensity = 2.2
	_env.glow_enabled = true
	_env.glow_bloom = 0.08
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 70.0
	_sun.rotation_degrees = Vector3(-48, -35, 0)
	add_child(_sun)


func _apply_time() -> void:
	var sm: ProceduralSkyMaterial = _env.sky.sky_material
	if _evening:
		_sun.light_color = Color("#7f8fd6")
		_sun.light_energy = 0.22
		sm.sky_top_color = Color("#1b2550")
		sm.sky_horizon_color = Color("#3a3f78")
		sm.ground_horizon_color = Color("#2a2a44")
		_env.ambient_light_energy = 0.4
		_env.glow_intensity = 0.7
		_env.tonemap_exposure = 1.0
	else:
		_sun.light_color = Color("#ffe2b5")
		_sun.light_energy = 1.05
		sm.sky_top_color = Color("#8fb6e8")
		sm.sky_horizon_color = Color("#f2dcb8")
		sm.ground_horizon_color = Color("#b9a27a")
		_env.ambient_light_energy = 0.45
		_env.glow_intensity = 0.3
		_env.tonemap_exposure = 0.82
	_night_lights = _night_lights.filter(func(l): return is_instance_valid(l))
	for l in _night_lights:
		l.visible = _evening
	for g in _glows:
		g[0].emission_energy_multiplier = g[2] if _evening else g[1]
	if _hud_loc != null:
		_hud_icon.texture = ArtLib.texture("ui.moon" if _evening else "ui.sun")


func _build_camera() -> void:
	_cam = Camera3D.new()
	# A long lens from far away: little size difference front to back, steady verticals.
	_cam.fov = cam["fov"]
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = float(cam["dist"]) + 6.0
	attrs.dof_blur_far_transition = 6.0
	attrs.dof_blur_near_enabled = true
	attrs.dof_blur_near_distance = float(cam["dist"]) - 5.0
	attrs.dof_blur_near_transition = 4.0
	attrs.dof_blur_amount = 0.07
	_cam.attributes = attrs
	add_child(_cam)
	_cam.current = true
	_follow(1.0)


func _follow(weight: float) -> void:
	var centre := Vector3(cam["cx"], 0, cam["cz"])
	var off := _player.position - centre
	var lean := Vector3(clampf(off.x * float(cam["lean_x"]), -8.0, 8.0), 0.0, clampf(off.z * float(cam["lean_z"]), -8.0, 8.0))
	var focus := centre + lean
	var pitch := deg_to_rad(float(cam["pitch"]))
	var back := Vector3(0, sin(pitch), cos(pitch)).rotated(Vector3.UP, deg_to_rad(float(cam["yaw"]))) * float(cam["dist"])
	_cam.fov = cam["fov"]
	_cam.attributes.dof_blur_far_distance = float(cam["dist"]) + 6.0
	_cam.attributes.dof_blur_near_distance = float(cam["dist"]) - 5.0
	_cam.position = _cam.position.lerp(focus + back, weight)
	_cam.look_at(_cam.position - back, Vector3.UP)


# --- ground --------------------------------------------------------------------------------------

func _paved(c: Vector2) -> bool:
	if c.length() < PLAZA_R:
		return true
	var ends: Array = [GATE_AT + Vector2(0, 4.0), Vector2(0.6, 9.0)]
	for b in _buildings:
		ends.append(_door_world(b))
	for e in ends:
		if Geometry2D.get_closest_point_to_segment(c, Vector2.ZERO, e).distance_to(c) < 0.8:
			return true
	return false


func _in_building(c: Vector2, pad: float = 0.0) -> bool:
	for b in _buildings:
		var rot: float = b["rot"]
		var rel: Vector2 = c - Vector2(b["at"])
		var local := Vector2(rel.x * cos(rot) - rel.y * sin(rot), rel.x * sin(rot) + rel.y * cos(rot))
		if absf(local.x) < float(b["w"]) / 2.0 + pad and absf(local.y) < float(b["d"]) / 2.0 + pad:
			return true
	return false


func _build_ground() -> void:
	var grass := StandardMaterial3D.new()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.03
	var nt := NoiseTexture2D.new()
	nt.noise = noise
	nt.seamless = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color("#5f8034"))
	ramp.set_color(1, Color("#8aa94a"))
	nt.color_ramp = ramp
	grass.albedo_texture = nt
	grass.uv1_scale = Vector3(8, 8, 8)
	grass.roughness = 0.95
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	g.mesh = pm
	g.material_override = grass
	add_child(g)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(cs)
	add_child(floor_body)
	# Walkable area: the plaza between the buildings.
	_solid_box(Vector3(0, 1, -8.6), Vector3(24, 2, 1))
	_solid_box(Vector3(0, 1, 7.6), Vector3(24, 2, 1))
	_solid_box(Vector3(-9.6, 1, 0), Vector3(1, 2, 20))
	_solid_box(Vector3(9.6, 1, 0), Vector3(1, 2, 20))
	_build_paving()


## Paving and lawn tufts follow the buildings' doors; rebuilt after a building moves.
func _build_paving() -> void:
	if _pave_root != null:
		_pave_root.queue_free()
	_pave_root = Node3D.new()
	add_child(_pave_root)
	# Paving: rings around the fountain, then laid stones out to the doors and the gate.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var stones: Array = []
	var ring := 1.28
	while ring < 2.9:
		var n := int(TAU * ring / 0.24)
		for i in n:
			var a := TAU * (i + rng.randf() * 0.25) / n
			stones.append([Vector2(cos(a), sin(a)) * ring, rng.randf_range(0.1, 0.13)])
		ring += 0.24
	var z := -9.0
	var row := 0
	while z < 9.5:
		var x := -11.0 + (0.12 if row % 2 == 0 else 0.0)
		while x < 11.0:
			var c := Vector2(x + rng.randf_range(-0.03, 0.03), z + rng.randf_range(-0.03, 0.03))
			if c.length() >= 2.95 and _paved(c) and not _in_building(c):
				stones.append([c, rng.randf_range(0.1, 0.13)])
			x += 0.25
		z += 0.23
		row += 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var stone := CylinderMesh.new()
	stone.top_radius = 0.85
	stone.bottom_radius = 1.0
	stone.height = 0.35
	stone.radial_segments = 8
	var smat := _mat(Color.WHITE, 0.9)
	smat.vertex_color_use_as_albedo = true
	stone.material = smat
	mm.mesh = stone
	mm.instance_count = stones.size()
	var sand := [Color("#cbb08a"), Color("#bea07a"), Color("#d8c19c"), Color("#b39574"), Color("#c7ab86"), Color("#a9927a")]
	for i in stones.size():
		var st: Array = stones[i]
		var c: Vector2 = st[0]
		var rad: float = st[1]
		var t := Transform3D(Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rad * rng.randf_range(1.0, 1.25), 0.15, rad)), Vector3(c.x, 0.02, c.y))
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, sand[rng.randi() % sand.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	_pave_root.add_child(mmi)
	# Mortar under the stones.
	var mortar := MultiMesh.new()
	mortar.transform_format = MultiMesh.TRANSFORM_3D
	var tile := BoxMesh.new()
	tile.size = Vector3(0.25, 0.01, 0.23)
	tile.material = _mat(Color("#8c7a60"))
	mortar.mesh = tile
	var cells: Array = []
	for i in 88:
		for j in 80:
			var c := Vector2(-11.0 + i * 0.25, -9.0 + j * 0.23)
			if _paved(c) and not _in_building(c):
				cells.append(c)
	mortar.instance_count = cells.size()
	for i in cells.size():
		mortar.set_instance_transform(i, Transform3D(Basis(), Vector3(cells[i].x, 0.004, cells[i].y)))
	var mo := MultiMeshInstance3D.new()
	mo.multimesh = mortar
	_pave_root.add_child(mo)
	_scatter_grass(rng)


func _scatter_grass(rng: RandomNumberGenerator) -> void:
	var tuft := MultiMesh.new()
	tuft.transform_format = MultiMesh.TRANSFORM_3D
	tuft.use_colors = true
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.05
	cone.height = 0.16
	cone.radial_segments = 5
	var tm := _mat(Color.WHITE)
	tm.vertex_color_use_as_albedo = true
	cone.material = tm
	tuft.mesh = cone
	var pts: Array = []
	for i in 5200:
		var c := Vector2(rng.randf_range(-14, 14), rng.randf_range(-12, 11))
		if not _paved(c) and not _in_building(c, 0.1):
			pts.append(c)
	tuft.instance_count = pts.size()
	for i in pts.size():
		var c: Vector2 = pts[i]
		tuft.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.7, 1.5)), Vector3(c.x, 0.07, c.y)))
		tuft.set_instance_color(i, Color("#557a2e").lerp(Color("#9dba55"), rng.randf()))
	var ti := MultiMeshInstance3D.new()
	ti.multimesh = tuft
	_pave_root.add_child(ti)


# --- buildings -----------------------------------------------------------------------------------

## Buildings around the fountain: game id, centre (x, z), size (w, d), facing (radians; 0 faces the
## camera, negative turns the front to the left), door offset along the front.
const BUILDINGS := [
	{"id": "home_building", "at": Vector2(0.05, -7.10), "w": 3.20, "d": 1.60, "h": 1.55, "rot": 0.0000, "door": 0.0},
	{"id": "shop_building", "at": Vector2(-6.10, -3.05), "w": 3.50, "d": 2.35, "h": 2.40, "rot": 0.8203, "door": 0.8},
	{"id": "card_room_building", "at": Vector2(8.10, -2.10), "w": 4.15, "d": 2.40, "h": 2.60, "rot": -0.8029, "door": 0.0},
	{"id": "community_hall_building", "at": Vector2(-7.70, 3.25), "w": 3.00, "d": 4.30, "h": 1.55, "rot": 1.6581, "door": 0.0},
]
const PLAZA_R := 4.3
## Where the gate out of the square stands (the path to the waterfront).
const GATE_AT := Vector2(3.5, 5.7)


const STYLES := {
	"shop_building": {"wall": "#efe0c4", "roof": "#c9573f", "trim": "#6b4428", "h": 2.4, "floors": 2},
	"home_building": {"wall": "#f1e6cf", "roof": "#6f9450", "trim": "#6b4428", "h": 2.0, "floors": 1},
	"card_room_building": {"wall": "#d8ccb6", "roof": "#35507a", "trim": "#5a3a24", "h": 2.6, "floors": 2},
	"community_hall_building": {"wall": "#e9dcc2", "roof": "#7a5a9a", "trim": "#6b4c30", "h": 2.2, "floors": 1},
}


func _door_world(b: Dictionary) -> Vector2:
	var rot: float = b["rot"]
	var local := Vector2(float(b["door"]), float(b["d"]) / 2.0 + 0.4)
	return Vector2(b["at"]) + Vector2(local.x * cos(rot) + local.y * sin(rot), -local.x * sin(rot) + local.y * cos(rot))


func _build_building(b: Dictionary) -> Node3D:
	var st: Dictionary = STYLES.get(b["id"], STYLES["home_building"])
	var w: float = b["w"]
	var d: float = b["d"]
	var root := Node3D.new()
	root.position = Vector3(b["at"].x, 0, b["at"].y)
	root.rotation.y = b["rot"]
	add_child(root)
	var body := StaticBody3D.new()
	var bcs := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(w, 2, d)
	bcs.shape = bshape
	body.add_child(bcs)
	body.position = Vector3(0, 1, 0)
	root.add_child(body)
	var h: float = float(b.get("h", st["h"]))
	body.set_meta("building", b["id"])
	var wall := _mat(Color(st["wall"]))
	var trim := _mat(Color(st["trim"]))
	var stone := _mat(Color("#a79a88"))
	_box(root, Vector3(w + 0.1, 0.35, d + 0.1), Vector3(0, 0.175, 0), stone)
	_box(root, Vector3(w, h, d), Vector3(0, 0.35 + h / 2.0, 0), wall)
	# Timber frame on the front and sides.
	for x in [-w / 2.0, -w / 6.0, w / 6.0, w / 2.0]:
		_box(root, Vector3(0.09, h, 0.06), Vector3(x, 0.35 + h / 2.0, d / 2.0 + 0.02), trim)
	for y in [0.35, 0.35 + h * 0.5, 0.35 + h]:
		_box(root, Vector3(w + 0.06, 0.08, 0.07), Vector3(0, y, d / 2.0 + 0.02), trim)
		_box(root, Vector3(0.07, 0.08, d + 0.06), Vector3(-w / 2.0 - 0.02, y, 0), trim)
		_box(root, Vector3(0.07, 0.08, d + 0.06), Vector3(w / 2.0 + 0.02, y, 0), trim)
	# Roof: a ridge along X with an overhang, then a chimney.
	var roof_h := 1.25 if st["floors"] == 1 else 1.1
	_prism(root, Vector3(d + 0.5, roof_h, w + 0.4), Vector3(0, 0.35 + h + roof_h / 2.0, 0), _mat(Color(st["roof"]), 0.75), PI / 2.0)
	_box(root, Vector3(0.35, 0.9, 0.35), Vector3(w * 0.32, 0.35 + h + roof_h * 0.6, -d * 0.15), stone)
	# Door on the front, where the data's door is.
	var dx: float = b["door"]
	_box(root, Vector3(0.6, 1.15, 0.08), Vector3(dx, 0.35 + 0.575, d / 2.0 + 0.05), _mat(Color("#7a4b2a")))
	_box(root, Vector3(0.8, 0.1, 0.12), Vector3(dx, 0.35 + 1.2, d / 2.0 + 0.06), trim)
	_box(root, Vector3(0.9, 0.18, 0.35), Vector3(dx, 0.09, d / 2.0 + 0.2), stone)
	_ball(root, 0.035, Vector3(dx + 0.2, 0.9, d / 2.0 + 0.1), _mat(Color("#e0b43a"), 0.3))
	# Warm windows with flower boxes.
	var win := _glow_mat(Color("#ffcf7a"), 0.15, 1.1)
	var floors: int = st["floors"]
	for f in floors:
		var wy := 0.35 + h * (0.35 if floors == 1 else (0.28 + 0.46 * f))
		for wx in [-w * 0.34, w * 0.34] + ([-w * 0.1, w * 0.12] if f == 1 else []):
			if absf(wx - dx) < 0.5 and f == 0:
				continue
			_box(root, Vector3(0.46, 0.5, 0.05), Vector3(wx, wy, d / 2.0 + 0.04), win)
			_box(root, Vector3(0.54, 0.07, 0.08), Vector3(wx, wy - 0.28, d / 2.0 + 0.07), trim)
			_box(root, Vector3(0.5, 0.12, 0.14), Vector3(wx, wy - 0.36, d / 2.0 + 0.12), _mat(Color("#8b5a3c")))
			for i in 4:
				_ball(root, 0.06, Vector3(wx - 0.18 + i * 0.12, wy - 0.28, d / 2.0 + 0.14), _mat([Color("#f7a8c0"), Color("#fff1d6"), Color("#b79be8"), Color("#ffd75e")][i]))
	# One warm light spilling from the front of each building in the evening.
	var spill := OmniLight3D.new()
	spill.light_color = Color("#ffb863")
	spill.light_energy = 0.9
	spill.omni_range = 3.2
	spill.position = Vector3(0, 1.2, d / 2.0 + 0.9)
	root.add_child(spill)
	_night_lights.append(spill)
	match b["id"]:
		"shop_building":
			for i in 8:
				var col := Color("#c9573f") if i % 2 == 0 else Color("#f3e6cc")
				var a := _box(root, Vector3(w * 0.9 / 8.0, 0.05, 0.7), Vector3(-w * 0.45 + (i + 0.5) * w * 0.9 / 8.0, 0.35 + h * 0.52, d / 2.0 + 0.35), _mat(col))
				a.rotation.x = 0.45
		"card_room_building":
			var plaque := _cyl(root, 0.32, 0.32, 0.06, Vector3(w / 2.0 + 0.2, 0.35 + h * 0.62, d / 2.0 + 0.1), _mat(Color("#2d3d63")))
			plaque.rotation.x = PI / 2.0
			_club(root, Vector3(w / 2.0 + 0.2, 0.35 + h * 0.62, d / 2.0 + 0.15), 0.1, _mat(Color("#f3e6cc")))
			for bx in [-w * 0.2, w * 0.2]:
				_box(root, Vector3(0.34, 0.8, 0.03), Vector3(dx + bx * 0.9, 0.35 + h * 0.36, d / 2.0 + 0.09), _mat(Color("#2f4a7a")))
				_club(root, Vector3(dx + bx * 0.9, 0.35 + h * 0.38, d / 2.0 + 0.12), 0.07, _mat(Color("#f3e6cc")))
			for lx in [-0.45, 0.45]:
				_lantern(root, Vector3(dx + lx, 0.35 + 1.1, d / 2.0 + 0.15))
		"community_hall_building":
			var clock := _cyl(root, 0.32, 0.32, 0.05, Vector3(dx, 0.35 + h + 0.45, d / 2.0 + 0.12), _mat(Color("#f7f0e0")))
			clock.rotation.x = PI / 2.0
			_box(root, Vector3(0.03, 0.2, 0.02), Vector3(dx, 0.35 + h + 0.52, d / 2.0 + 0.16), trim)
			_box(root, Vector3(0.15, 0.03, 0.02), Vector3(dx + 0.07, 0.35 + h + 0.45, d / 2.0 + 0.16), trim)
			for bx in [-0.75, 0.75]:
				_box(root, Vector3(0.3, 0.8, 0.03), Vector3(dx + bx, 0.35 + h * 0.4, d / 2.0 + 0.09), _mat(Color("#6a4a8e")))

	return root


## A club: three balls and a stem, facing the camera.
func _club(parent: Node3D, at: Vector3, s: float, mat: Material) -> void:
	_ball(parent, s * 0.55, at + Vector3(0, s * 0.55, 0), mat, Vector3(1, 1, 0.4))
	_ball(parent, s * 0.55, at + Vector3(-s * 0.5, 0, 0), mat, Vector3(1, 1, 0.4))
	_ball(parent, s * 0.55, at + Vector3(s * 0.5, 0, 0), mat, Vector3(1, 1, 0.4))
	_box(parent, Vector3(s * 0.25, s * 0.9, s * 0.2), at + Vector3(0, -s * 0.5, 0), mat)


func _lantern(parent: Node3D, at: Vector3) -> void:
	_box(parent, Vector3(0.16, 0.22, 0.16), at, _glow_mat(Color("#ffc46b"), 0.3, 1.6))
	_box(parent, Vector3(0.2, 0.04, 0.2), at + Vector3(0, 0.13, 0), _mat(Color("#2a2320")))
	var l := OmniLight3D.new()
	l.light_color = Color("#ffb863")
	l.light_energy = 1.1
	l.omni_range = 2.6
	l.position = at
	parent.add_child(l)
	_night_lights.append(l)


# --- props ---------------------------------------------------------------------------------------

func _p(x: float, z: float) -> Vector3:
	return Vector3(x, 0, z)


## Props laid out for the camera: flower beds and lamps between the fountain and the buildings,
## the notice board and a bench at the sides, trees and fences framing the edges.
func _build_decor() -> void:
	_fountain(Vector3.ZERO)
	# flower beds (raised borders) ring the plaza without blocking the paths
	for bed in [[-1.9, -3.6, 1.7, 0.9], [2.3, -3.8, 1.7, 0.9], [-3.4, -1.9, 1.3, 1.0], [3.6, -2.7, 1.2, 0.9],
			[-2.4, 3.3, 1.8, 0.9], [2.1, 3.6, 1.5, 0.9], [-5.6, 2.4, 1.6, 1.0], [5.7, 1.2, 1.2, 1.4], [-5.8, -3.6, 1.2, 0.8]]:
		_bed(_p(bed[0], bed[1]), bed[2], bed[3])
	for at in [_p(-3.2, -3.0), _p(-2.1, 3.0), _p(4.3, -3.6), _p(4.7, 2.7), _p(2.8, 5.8), _p(4.2, 5.8), _p(-1.0, -4.6)]:
		_lamp(at)
	_board(_p(-3.6, 1.5), 0.35)
	_bench(_p(5.0, 0.9), -1.25)
	_bench(_p(-4.3, -0.4), 1.2)
	_booth(_p(7.4, 2.5), -0.55)
	_aframe(_p(5.1, -1.3))
	_crates(_p(-6.9, -4.3))
	_crates(_p(-2.6, -5.0))
	_pot(_p(-0.5, -4.9))
	_pot(_p(1.1, -4.9))
	_pot(_p(5.4, -2.3))
	_pot(_p(-5.6, 0.9))
	_mailbox(_p(1.9, -4.8))
	_gate(Vector3(GATE_AT.x, 0, GATE_AT.y))
	# framing: trees behind and at the sides, fences, big bushes in the near corners
	for t in [[-9.8, -8.4, false], [-2.4, -8.9, true], [3.4, -9.0, false], [9.9, -7.4, true], [-10.4, 3.9, false],
			[10.5, 4.6, false], [-8.9, -5.6, true], [9.6, -1.2, false], [-6.0, -8.2, false], [6.2, -7.8, false]]:
		_tree(_p(t[0], t[1]), Color("#f0b3c4") if t[2] else Color("#6a9440"), 1.25)
	_fence(_p(-10, -8.0), _p(10, -8.0))
	_fence(_p(-9.0, 6.4), _p(-1.4, 6.4))
	_fence(_p(9.2, 0.5), _p(9.2, 6.4))
	for b in [[-7.6, 5.4], [-6.2, 5.9], [-4.4, 6.0], [6.6, 5.2], [8.2, 4.8], [-9.3, 4.6], [9.2, 6.2]]:
		_bush(_p(b[0], b[1]), 1.8)
	# near corners: big trees that frame the view
	_tree(_p(-8.8, 6.3), Color("#5f8a3a"), 1.5)
	_tree(_p(8.9, 6.6), Color("#6a9440"), 1.4)
	for b in [[-8.3, 2.1], [8.6, -4.8], [-1.4, -7.3], [2.4, -7.2]]:
		_bush(_p(b[0], b[1]), 1.1)


## A raised flower bed: low stone border, soil, and a mound of mixed flowers.
func _bed(at: Vector3, w: float, d: float) -> void:
	var stone := _mat(Color("#a89a86"))
	_box(self, Vector3(w + 0.12, 0.2, d + 0.12), at + Vector3(0, 0.1, 0), stone)
	_box(self, Vector3(w, 0.22, d), at + Vector3(0, 0.12, 0), _mat(Color("#5a4230")))
	_ball(self, 0.5, at + Vector3(0, 0.22, 0), _mat(Color("#5e8a38")), Vector3(w * 0.95, 0.5, d * 0.95))
	var cols := [Color("#f7a8c0"), Color("#fff1d6"), Color("#ffd75e"), Color("#b79be8"), Color("#e8894a"), Color("#c9a0f0")]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(at.x * 100 + at.z * 7)
	for i in int(w * d * 22):
		var q := Vector3(rng.randf_range(-w / 2.0 + 0.1, w / 2.0 - 0.1), 0, rng.randf_range(-d / 2.0 + 0.1, d / 2.0 - 0.1))
		_ball(self, rng.randf_range(0.05, 0.08), at + q + Vector3(0, 0.42 + rng.randf() * 0.1, 0), _mat(cols[rng.randi() % cols.size()]))
	_solid_box(at + Vector3(0, 1, 0), Vector3(w, 2, d))


func _fence(a: Vector3, b: Vector3) -> void:
	var wood := _mat(Color("#8a6040"))
	var n := int(a.distance_to(b) / 0.9)
	var dir := (b - a).normalized()
	var ang := atan2(dir.x, dir.z)
	for i in n + 1:
		_box(self, Vector3(0.1, 0.8, 0.1), a + dir * (i * 0.9) + Vector3(0, 0.4, 0), wood)
	for y in [0.35, 0.65]:
		var rail := _box(self, Vector3(0.06, 0.07, a.distance_to(b)), (a + b) / 2.0 + Vector3(0, y, 0), wood)
		rail.rotation.y = ang


func _mailbox(at: Vector3) -> void:
	_box(self, Vector3(0.08, 0.8, 0.08), at + Vector3(0, 0.4, 0), _mat(Color("#6b4a30")))
	_box(self, Vector3(0.3, 0.26, 0.22), at + Vector3(0, 0.9, 0), _mat(Color("#c9473f")))


func _fountain(at: Vector3) -> void:
	var stone := _mat(Color("#cfc4b0"))
	_cyl(self, 0.95, 1.0, 0.4, at + Vector3(0, 0.2, 0), stone, 36)
	var water := _mat(Color("#5fa8b8"), 0.08)
	water.metallic = 0.2
	_cyl(self, 0.86, 0.86, 0.36, at + Vector3(0, 0.21, 0), water, 36)
	_cyl(self, 0.16, 0.22, 0.8, at + Vector3(0, 0.6, 0), stone)
	_cyl(self, 0.42, 0.18, 0.18, at + Vector3(0, 1.0, 0), stone)
	_cyl(self, 0.36, 0.36, 0.12, at + Vector3(0, 1.06, 0), water)
	_cyl(self, 0.08, 0.1, 0.4, at + Vector3(0, 1.25, 0), stone)
	var spray := _glow_mat(Color("#dff4ff"), 0.4, 0.8)
	_cyl(self, 0.03, 0.08, 0.35, at + Vector3(0, 1.55, 0), spray)
	var suits := [Color("#c9473f"), Color("#2b2320"), Color("#c9473f"), Color("#2b2320")]
	for i in 4:
		var a := PI / 2.0 + i * PI / 2.0 - PI / 4.0
		var p := at + Vector3(cos(a) * 1.0, 0.24, sin(a) * 1.0)
		var s := _box(self, Vector3(0.18, 0.18, 0.02), p, _mat(suits[i]), -a + PI / 2.0)
		s.rotation.z = PI / 4.0
	_solid_round(at, 1.0)


func _tree(at: Vector3, leaf: Color, k: float = 1.0) -> void:
	_cyl(self, 0.1 * k, 0.14 * k, 1.0 * k, at + Vector3(0, 0.5 * k, 0), _mat(Color("#6b4a30")))
	var m := _mat(leaf)
	var m2 := _mat(leaf.darkened(0.12))
	_ball(self, 0.62 * k, at + Vector3(0, 1.35 * k, 0), m)
	_ball(self, 0.45 * k, at + Vector3(-0.38, 1.15, 0.12) * k, m2)
	_ball(self, 0.45 * k, at + Vector3(0.38, 1.2, -0.05) * k, m2)
	_ball(self, 0.4 * k, at + Vector3(0.05, 1.75, 0.05) * k, m)
	_solid_round(at, 0.25)


func _bush(at: Vector3, k: float = 1.0) -> void:
	var m := _mat(Color("#5f8f3c"))
	_ball(self, 0.26 * k, at + Vector3(0, 0.2 * k, 0), m, Vector3(1, 0.8, 1))
	_ball(self, 0.2 * k, at + Vector3(0.2, 0.16, 0.05) * k, m, Vector3(1, 0.8, 1))
	for i in 5:
		_ball(self, 0.04, at + Vector3(-0.15 + i * 0.08, 0.36, 0.12), _mat([Color("#f7a8c0"), Color("#fff1d6"), Color("#b79be8")][i % 3]))
	_solid_round(at, 0.28)


func _planter(at: Vector3) -> void:
	_box(self, Vector3(1.1, 0.28, 0.4), at + Vector3(0, 0.14, -0.2), _mat(Color("#8b5a3c")))
	var cols := [Color("#f7a8c0"), Color("#fff1d6"), Color("#ffd75e"), Color("#b79be8"), Color("#e8894a")]
	for i in 14:
		var back := 1.0 if i >= 7 else 0.0
		_ball(self, 0.07, at + Vector3(-0.48 + (i % 7) * 0.16, 0.34 + 0.04 * back, -0.28 + 0.14 * back), _mat(cols[i % cols.size()]))
	_solid_box(at + Vector3(0, 1, -0.2), Vector3(1.1, 2, 0.4))


func _lamp(at: Vector3) -> void:
	var iron := _mat(Color("#2a2522"), 0.5)
	_cyl(self, 0.05, 0.07, 1.9, at + Vector3(0, 0.95, 0), iron, 8)
	_cyl(self, 0.12, 0.14, 0.1, at + Vector3(0, 0.05, 0), iron, 8)
	_lantern(self, at + Vector3(0, 2.02, 0))
	_solid_round(at, 0.12)


func _bench(at: Vector3, rot: float = 0.0) -> void:
	var n := Node3D.new()
	n.position = at
	n.rotation.y = rot
	add_child(n)
	var wood := _mat(Color("#8a5a36"))
	_box(n, Vector3(1.1, 0.07, 0.36), Vector3(0, 0.36, 0), wood)
	_box(n, Vector3(1.1, 0.26, 0.06), Vector3(0, 0.58, -0.17), wood)
	for x in [-0.46, 0.46]:
		_box(n, Vector3(0.06, 0.36, 0.32), Vector3(x, 0.18, 0), _mat(Color("#2a2522")))
	_solid_round(at, 0.45)


func _board(at: Vector3, rot: float = 0.0) -> void:
	var holder := Node3D.new()
	holder.position = at
	holder.rotation.y = rot
	add_child(holder)
	_board_parts(holder)
	_solid_round(at, 0.5)


func _board_parts(n: Node3D) -> void:
	var at := Vector3.ZERO
	var wood := _mat(Color("#7a5230"))
	for x in [-0.36, 0.36]:
		_box(n, Vector3(0.1, 1.6, 0.1), at + Vector3(x, 0.65, 0), wood)
	_box(n, Vector3(1.2, 0.8, 0.08), at + Vector3(0, 0.95, 0), _mat(Color("#9c6b42")))
	_prism(n, Vector3(1.05, 0.18, 0.25), at + Vector3(0, 1.36, 0), _mat(Color("#5f7a4a")))
	for i in 4:
		_box(n, Vector3(0.16, 0.2, 0.01), at + Vector3(-0.3 + i * 0.2, 0.95 + (0.08 if i % 2 == 0 else -0.06), 0.04), _mat(Color("#fbf1dc")))


func _booth(at: Vector3, rot: float = 0.0) -> void:
	var holder := Node3D.new()
	holder.position = at
	holder.rotation.y = rot
	add_child(holder)
	_booth_parts(holder)
	_solid_round(at, 0.8)


func _booth_parts(n: Node3D) -> void:
	var at := Vector3.ZERO
	var wood := _mat(Color("#8a5a36"))
	_box(n, Vector3(1.2, 0.7, 0.5), at + Vector3(0, 0.35, 0), wood)
	for x in [-0.55, 0.55]:
		_box(n, Vector3(0.07, 1.5, 0.07), at + Vector3(x, 0.75, 0.2), wood)
	for i in 6:
		var a := _box(n, Vector3(0.2, 0.05, 0.7), at + Vector3(-0.5 + i * 0.2, 1.45, 0.1), _mat(Color("#3f7f7a") if i % 2 == 0 else Color("#f3e6cc")))
		a.rotation.x = 0.35
	for i in 5:
		_ball(n, 0.08, at + Vector3(-0.4 + i * 0.2, 0.76, 0.1), _mat([Color("#e8894a"), Color("#c9473f"), Color("#ffd75e")][i % 3]))


func _crates(at: Vector3) -> void:
	var wood := _mat(Color("#a3764a"))
	_box(self, Vector3(0.4, 0.4, 0.4), at + Vector3(0, 0.2, 0), wood)
	_box(self, Vector3(0.32, 0.32, 0.32), at + Vector3(0.05, 0.56, 0), wood, 0.3)
	_cyl(self, 0.16, 0.16, 0.42, at + Vector3(0.38, 0.21, 0.05), _mat(Color("#7a5230")))
	_solid_round(at, 0.3)


func _pot(at: Vector3) -> void:
	_cyl(self, 0.14, 0.1, 0.24, at + Vector3(0, 0.12, 0), _mat(Color("#c46a45")))
	_ball(self, 0.17, at + Vector3(0, 0.34, 0), _mat(Color("#6f9a45")))


func _aframe(at: Vector3) -> void:
	var board := _box(self, Vector3(0.42, 0.62, 0.04), at + Vector3(0, 0.32, 0.08), _mat(Color("#2d3b33")))
	board.rotation.x = -0.25
	_club(self, at + Vector3(0, 0.36, 0.12), 0.08, _mat(Color("#f3e6cc")))


func _signpost(at: Vector3) -> void:
	var wood := _mat(Color("#8a5a36"))
	_box(self, Vector3(0.08, 1.1, 0.08), at + Vector3(0, 0.55, 0), wood)
	for i in 3:
		_box(self, Vector3(0.5, 0.12, 0.04), at + Vector3(0.12 * (1 if i % 2 == 0 else -1), 0.95 - i * 0.18, 0.04), wood)


func _gate(at: Vector3) -> void:
	var wood := _mat(Color("#7a5230"))
	for x in [-0.55, 0.55]:
		_box(self, Vector3(0.14, 1.7, 0.14), at + Vector3(x, 0.85, 0), wood)
		_box(self, Vector3(0.24, 0.2, 0.24), at + Vector3(x, 0.1, 0), _mat(Color("#a79a88")))
	_box(self, Vector3(1.4, 0.16, 0.18), at + Vector3(0, 1.72, 0), wood)
	var ivy := _mat(Color("#5f8f3c"))
	for i in 6:
		_ball(self, 0.1, at + Vector3(-0.6 + i * 0.24, 1.8, 0.02), ivy)
	_box(self, Vector3(0.36, 0.26, 0.03), at + Vector3(0, 1.45, 0.05), _mat(Color("#2f4a7a")))


# --- people --------------------------------------------------------------------------------------

func _build_people() -> void:
	_player = CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.22
	cap.height = 0.9
	cs.shape = cap
	cs.position = Vector3(0, 0.45, 0)
	_player.add_child(cs)
	_player.position = Vector3(0.1, 0, 2.7)
	add_child(_player)
	_player_body = _person(_player, Color("#d9a441"), Color("#6b3f24"), Color("#3f7f7a"))
	# Who is in the square follows the game's schedule; where they stand follows the composition.
	var places := {"npc_lumi": "fox", "npc_moa": "fairy", "npc_juno": "bird"}
	var spots := {"npc_lumi": Vector3(1.3, 0, 2.2), "npc_moa": Vector3(-2.3, 0, -1.3), "npc_juno": Vector3(5.8, 0, 0.1)}
	for id in places:
		var place: Dictionary = Game.data.npc_place(id, "evening" if _evening else "day", Game.state if Game.state != null else GameState.new())
		if str(place.get("loc", "")) != "village_square":
			continue
		var node := Node3D.new()
		node.position = spots[id]
		add_child(node)
		match places[id]:
			"fox":
				_fox(node)
				_lumi = node
			"fairy":
				_fairy(node)
			"bird":
				_bird(node)


## A chibi person: big head, small body (about 1 m tall).
func _person(parent: Node3D, coat: Color, hair: Color, scarf: Color) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	var skin := _mat(Color("#f6d7bd"))
	for x in [-0.08, 0.08]:
		_cyl(n, 0.055, 0.06, 0.24, Vector3(x, 0.12, 0), _mat(Color("#5a3a28")), 10)
	_cyl(n, 0.16, 0.22, 0.42, Vector3(0, 0.44, 0), _mat(coat), 16)
	_cyl(n, 0.2, 0.19, 0.08, Vector3(0, 0.66, 0), _mat(scarf), 16)
	_ball(n, 0.24, Vector3(0, 0.9, 0), skin)
	_ball(n, 0.26, Vector3(0, 0.98, -0.04), _mat(hair), Vector3(1.05, 0.8, 1.05))
	_eyes(n, Vector3(0, 0.88, 0.22), 0.08)
	_box(n, Vector3(0.14, 0.14, 0.06), Vector3(0.2, 0.42, 0.05), _mat(Color("#7a4b2a")))
	return n


func _eyes(parent: Node3D, at: Vector3, gap: float) -> void:
	var ink := _mat(Color("#2b1f18"), 0.3)
	for s in [-1.0, 1.0]:
		_ball(parent, 0.028, at + Vector3(s * gap, 0, 0), ink)


func _fox(n: Node3D) -> void:
	var fur := _mat(Color("#e8894a"))
	var cream := _mat(Color("#fff1dc"))
	for x in [-0.08, 0.08]:
		_cyl(n, 0.055, 0.06, 0.22, Vector3(x, 0.11, 0), _mat(Color("#5a3a28")), 10)
	_cyl(n, 0.15, 0.2, 0.4, Vector3(0, 0.42, 0), _mat(Color("#b8403a")), 16)
	_ball(n, 0.25, Vector3(0, 0.86, 0), fur)
	_ball(n, 0.11, Vector3(0, 0.8, 0.19), cream, Vector3(1.2, 0.8, 1))
	_ball(n, 0.03, Vector3(0, 0.82, 0.29), _mat(Color("#2b1f18")))
	for s in [-1.0, 1.0]:
		var ear := _prism(n, Vector3(0.16, 0.24, 0.07), Vector3(s * 0.14, 1.12, 0), fur)
		ear.rotation.z = -s * 0.25
	_eyes(n, Vector3(0, 0.9, 0.22), 0.09)
	var tail := _ball(n, 0.16, Vector3(0.24, 0.35, -0.2), fur, Vector3(0.9, 1.5, 0.9))
	tail.rotation.z = -0.8
	_ball(n, 0.08, Vector3(0.36, 0.52, -0.26), cream)


func _fairy(n: Node3D) -> void:
	var body := Node3D.new()
	body.position = Vector3(0, 0.55, 0)
	n.add_child(body)
	_bobbers.append([body, 0.55, 2.4, 0.08])
	_cyl(body, 0.2, 0.2, 0.08, Vector3(0, 0.0, 0), _mat(Color("#c9473f")), 16)
	for i in 8:
		var a := TAU * i / 8.0
		_box(body, Vector3(0.06, 0.085, 0.05), Vector3(cos(a) * 0.19, 0, sin(a) * 0.19), _mat(Color("#f3e6cc")), -a)
	_cyl(body, 0.07, 0.09, 0.16, Vector3(0, 0.1, 0), _mat(Color("#fff1dc")), 10)
	_ball(body, 0.14, Vector3(0, 0.3, 0), _mat(Color("#f6d7bd")))
	_ball(body, 0.15, Vector3(0, 0.35, -0.03), _mat(Color("#f2c94c")), Vector3(1.05, 0.75, 1.05))
	_ball(body, 0.07, Vector3(0, 0.48, -0.06), _mat(Color("#f2c94c")))
	_eyes(body, Vector3(0, 0.29, 0.13), 0.05)
	var wing := _mat(Color(0.92, 0.97, 1.0, 0.55), 0.2)
	wing.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for s in [-1.0, 1.0]:
		var wg := _ball(body, 0.18, Vector3(s * 0.2, 0.2, -0.08), wing, Vector3(1.0, 1.4, 0.15))
		wg.rotation.z = s * 0.5


func _bird(n: Node3D) -> void:
	var coral := _mat(Color("#e07a5f"))
	for x in [-0.07, 0.07]:
		_cyl(n, 0.02, 0.02, 0.24, Vector3(x, 0.12, 0), _mat(Color("#8a5a36")), 6)
	_ball(n, 0.3, Vector3(0, 0.5, 0), coral)
	_ball(n, 0.2, Vector3(0, 0.46, 0.14), _mat(Color("#f2cc8f")), Vector3(1, 1.1, 0.8))
	var beak := _prism(n, Vector3(0.1, 0.12, 0.08), Vector3(0, 0.62, 0.3), _mat(Color("#f2a33a")))
	beak.rotation.x = PI / 2.0
	_eyes(n, Vector3(0, 0.7, 0.24), 0.1)
	_box(n, Vector3(0.18, 0.07, 0.04), Vector3(0, 0.4, 0.29), _mat(Color("#2b2320")))
	for i in 5:
		var card := _box(n, Vector3(0.16, 0.24, 0.02), Vector3(-0.2 + i * 0.1, 0.62, -0.3), _mat(Color("#35507a")))
		card.rotation.z = -0.5 + i * 0.25
	for i in 3:
		var crest := _box(n, Vector3(0.07, 0.12, 0.02), Vector3(-0.07 + i * 0.07, 0.86, 0.05), _mat(Color("#fff1dc")))
		crest.rotation.z = -0.3 + i * 0.3


# --- HUD -----------------------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := UiKit.panel(UiKit.PAPER, 10)
	panel.position = Vector2(16, 14)
	layer.add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var chip := UiKit.icon("ui.chip", 26)
	if chip != null:
		row.add_child(chip)
	row.add_child(UiKit.label("칩 40", 22))
	col.add_child(UiKit.label("목표 · 루미에게 인사하기", 17, UiKit.ACCENT))
	var tag := UiKit.panel(UiKit.PAPER, 8)
	tag.position = Vector2(1280 - 200, 14)
	layer.add_child(tag)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 6)
	tag.add_child(trow)
	_hud_icon = UiKit.icon("ui.sun", 22)
	if _hud_icon == null:
		_hud_icon = TextureRect.new()
	trow.add_child(_hud_icon)
	_hud_loc = UiKit.label("마을 광장", 17)
	trow.add_child(_hud_loc)
	_prompt = UiKit.button("E  대화하기", 180, false)
	_prompt.position = Vector2(640 - 90, 640)
	_prompt.visible = false
	layer.add_child(_prompt)
	var hint := UiKit.label("3D 시안 · WASD 이동 · T 낮/저녁 · F1 편집 · Esc 종료", 14, Color(1, 1, 1, 0.85))
	hint.position = Vector2(16, 690)
	layer.add_child(hint)
	_apply_time()


# --- loop ----------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_player.velocity = Vector3(dir.x, 0, dir.y) * WALK
	_player.move_and_slide()
	_player.position.y = 0.0
	if dir != Vector2.ZERO:
		_player_body.rotation.y = lerp_angle(_player_body.rotation.y, atan2(dir.x, dir.y), 0.25)
		_player_body.position.y = absf(sin(_t * 12.0)) * 0.05
	else:
		_player_body.position.y = 0.0
	for b in _bobbers:
		b[0].position.y = b[1] + sin(_t * b[2]) * b[3]
	_follow(1.0 if _edit else clampf(delta * 5.0, 0.0, 1.0))
	if _pave_dirty > 0.0:
		_pave_dirty -= delta
		if _pave_dirty <= 0.0:
			_build_paving()
	if _lumi != null:
		_prompt.visible = _player.position.distance_to(_lumi.position) < 1.3


func _unhandled_input(event: InputEvent) -> void:
	if _edit:
		_edit_input(event)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_set_edit(not _edit)
		elif event.keycode == KEY_T:
			_evening = not _evening
			_apply_time()
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()


func _take_shot() -> void:
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shot)
	print("[diorama] screenshot ", _shot)
	get_tree().quit()


# --- edit mode -----------------------------------------------------------------------------------

const BUILDING_NAMES := {"home_building": "내 집", "shop_building": "잡화점", "card_room_building": "카드룸", "community_hall_building": "마을 회관"}


func _load_layout() -> void:
	if not FileAccess.file_exists(LAYOUT_FILE):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_FILE))
	if not data is Dictionary:
		return
	for k in data.get("camera", {}):
		if cam.has(k):
			cam[k] = float(data["camera"][k])
		elif k == "lean":
			cam["lean_x"] = float(data["camera"][k])
			cam["lean_z"] = float(data["camera"][k])
	for saved in data.get("buildings", []):
		for b in _buildings:
			if b["id"] == saved.get("id", ""):
				b["at"] = Vector2(float(saved["at"][0]), float(saved["at"][1]))
				b["rot"] = deg_to_rad(float(saved["rot_deg"]))
				for k in ["w", "d", "h", "door"]:
					if saved.has(k):
						b[k] = float(saved[k])


func _save_layout() -> void:
	var out := {"camera": cam.duplicate(), "buildings": []}
	for b in _buildings:
		out["buildings"].append({"id": b["id"], "at": [snappedf(b["at"].x, 0.01), snappedf(b["at"].y, 0.01)],
			"rot_deg": snappedf(rad_to_deg(b["rot"]), 0.1), "w": snappedf(b["w"], 0.01), "d": snappedf(b["d"], 0.01),
			"h": snappedf(float(b.get("h", STYLES[b["id"]]["h"])), 0.01), "door": b["door"]})
	var f := FileAccess.open(LAYOUT_FILE, FileAccess.WRITE)
	if f == null:
		_sel_label.text = "저장 실패: " + LAYOUT_FILE
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	_sel_label.text = "저장됨: diorama/layout.json"


func _reset_layout() -> void:
	cam = CAM_DEFAULT.duplicate()
	_buildings = BUILDINGS.duplicate(true)
	for i in _buildings.size():
		_rebuild_building(i)
	_pave_dirty = 0.05
	_sync_sliders()


func _build_editor() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_edit_panel = UiKit.panel(UiKit.PAPER, 12)
	_edit_panel.position = Vector2(1280 - 356, 64)
	_edit_panel.custom_minimum_size = Vector2(340, 0)
	_edit_panel.visible = false
	layer.add_child(_edit_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_edit_panel.add_child(col)
	col.add_child(UiKit.label("카메라", 17, UiKit.ACCENT))
	_slider_row(col, "persp", "원근감", 8, 60, 0.5)
	_slider_row(col, "cam.dist", "거리", 5, 80, 0.5)
	_slider_row(col, "cam.fov", "줌 (화각)", 6, 60, 0.5)
	_slider_row(col, "cam.pitch", "내려다보는 각도", 15, 85, 1)
	_slider_row(col, "cam.yaw", "좌우 회전", -60, 60, 1)
	_slider_row(col, "cam.cx", "중심 X", -8, 8, 0.1)
	_slider_row(col, "cam.cz", "중심 Z", -8, 8, 0.1)
	_slider_row(col, "cam.lean_x", "따라가기 좌우", 0, 1, 0.05)
	_slider_row(col, "cam.lean_z", "따라가기 앞뒤", 0, 1, 0.05)
	var head := HBoxContainer.new()
	col.add_child(head)
	var prev := UiKit.button("◀", 40, false)
	prev.pressed.connect(func(): _select((_sel + _buildings.size() - 1) % _buildings.size()))
	var next := UiKit.button("▶", 40, false)
	next.pressed.connect(func(): _select((_sel + 1) % _buildings.size()))
	_sel_label = UiKit.label("", 17, UiKit.ACCENT)
	_sel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(prev)
	head.add_child(_sel_label)
	head.add_child(next)
	_slider_row(col, "b.x", "위치 X", -12, 12, 0.05)
	_slider_row(col, "b.z", "위치 Z", -12, 12, 0.05)
	_slider_row(col, "b.rot", "방향 (도)", -180, 180, 1)
	_slider_row(col, "b.w", "폭", 1.5, 8, 0.05)
	_slider_row(col, "b.d", "깊이", 1.5, 8, 0.05)
	_slider_row(col, "b.h", "벽 높이", 1.2, 5, 0.05)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	var save := UiKit.button("저장", 90, false)
	save.pressed.connect(_save_layout)
	var reset := UiKit.button("처음 값", 90, false)
	reset.pressed.connect(_reset_layout)
	row.add_child(save)
	row.add_child(reset)
	col.add_child(UiKit.wrap_label("원근감: 올리면 뒤가 더 작아짐(화면 크기는 유지)\n건물 클릭: 선택 · 드래그: 이동 · Q/E: 회전\n휠: 줌 · 오른쪽 드래그: 회전 · 가운데 드래그: 이동 · F1: 닫기", 13, UiKit.MUTED))
	_sel_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.95
	torus.outer_radius = 1.0
	_sel_ring.mesh = torus
	var rm := _mat(Color("#ffd23f"), 0.3)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sel_ring.material_override = rm
	_sel_ring.visible = false
	add_child(_sel_ring)
	_select(0)


func _slider_row(parent: Control, key: String, label: String, lo: float, hi: float, step: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := UiKit.label(label, 14)
	l.custom_minimum_size = Vector2(104, 0)
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.custom_minimum_size = Vector2(120, 22)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.focus_mode = Control.FOCUS_NONE
	row.add_child(sl)
	var val := UiKit.label("", 13, UiKit.MUTED)
	val.custom_minimum_size = Vector2(46, 0)
	row.add_child(val)
	_sliders[key] = [sl, val]
	sl.value_changed.connect(func(v: float): _on_slider(key, v))


func _on_slider(key: String, v: float) -> void:
	_sliders[key][1].text = str(snappedf(v, 0.01))
	if key == "persp":
		_set_perspective(v)
		return
	if key.begins_with("cam."):
		cam[key.substr(4)] = v
		return
	var b: Dictionary = _buildings[_sel]
	match key:
		"b.x":
			b["at"] = Vector2(v, b["at"].y)
		"b.z":
			b["at"] = Vector2(b["at"].x, v)
		"b.rot":
			b["rot"] = deg_to_rad(v)
		"b.w", "b.d", "b.h":
			b[key.substr(2)] = v
	_rebuild_building(_sel)
	_pave_dirty = 0.35


## Dolly zoom: a wider view from closer by, keeping the square the same size on screen, so
## things further back look smaller. `fov` is the new field of view in degrees.
func _set_perspective(fov: float) -> void:
	var keep := float(cam["dist"]) * tan(deg_to_rad(float(cam["fov"]) / 2.0))
	cam["fov"] = fov
	cam["dist"] = keep / tan(deg_to_rad(fov / 2.0))
	_sync_sliders()


func _sync_sliders() -> void:
	if _sliders.has("persp"):
		_sliders["persp"][0].set_value_no_signal(cam["fov"])
		_sliders["persp"][1].text = str(snappedf(cam["fov"], 0.1)) + "°"
	for k in cam:
		if _sliders.has("cam." + k):
			_sliders["cam." + k][0].set_value_no_signal(cam[k])
			_sliders["cam." + k][1].text = str(snappedf(cam[k], 0.01))
	var b: Dictionary = _buildings[_sel]
	var vals := {"b.x": b["at"].x, "b.z": b["at"].y, "b.rot": rad_to_deg(b["rot"]), "b.w": b["w"], "b.d": b["d"],
		"b.h": float(b.get("h", STYLES[b["id"]]["h"]))}
	for k in vals:
		_sliders[k][0].set_value_no_signal(vals[k])
		_sliders[k][1].text = str(snappedf(vals[k], 0.01))
	_sel_label.text = BUILDING_NAMES.get(b["id"], b["id"])
	_sel_ring.position = Vector3(b["at"].x, 0.05, b["at"].y)
	var r := maxf(float(b["w"]), float(b["d"])) * 0.62
	_sel_ring.scale = Vector3(r, 1, r)


func _select(i: int) -> void:
	_sel = i
	_sync_sliders()


func _rebuild_building(i: int) -> void:
	if i < _building_roots.size() and is_instance_valid(_building_roots[i]):
		_building_roots[i].queue_free()
	var root := _build_building(_buildings[i])
	if i < _building_roots.size():
		_building_roots[i] = root
	else:
		_building_roots.append(root)
	_night_lights = _night_lights.filter(func(l): return is_instance_valid(l) and not l.is_queued_for_deletion())
	_apply_time()
	if i == _sel:
		_sync_sliders()


func _set_edit(on: bool) -> void:
	_edit = on
	_edit_panel.visible = on
	_sel_ring.visible = on
	_sync_sliders()


func _ground_point(screen: Vector2) -> Variant:
	return Plane(Vector3.UP, 0.0).intersects_ray(_cam.project_ray_origin(screen), _cam.project_ray_normal(screen))


func _edit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam["fov"] = clampf(float(cam["fov"]) - 0.8, 6.0, 60.0)
			_sync_sliders()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam["fov"] = clampf(float(cam["fov"]) + 0.8, 6.0, 60.0)
			_sync_sliders()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var from := _cam.project_ray_origin(mb.position)
				var q := PhysicsRayQueryParameters3D.create(from, from + _cam.project_ray_normal(mb.position) * 200.0)
				var hit := get_world_3d().direct_space_state.intersect_ray(q)
				if not hit.is_empty() and hit["collider"].has_meta("building"):
					for i in _buildings.size():
						if _buildings[i]["id"] == hit["collider"].get_meta("building"):
							_select(i)
					_dragging = "building"
			else:
				_dragging = ""
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = "orbit" if mb.pressed else ""
			_drag_from = mb.position
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = "pan" if mb.pressed else ""
			_drag_from = mb.position
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		match _dragging:
			"building":
				var p = _ground_point(mm.position)
				if p != null:
					_buildings[_sel]["at"] = Vector2(snappedf(p.x, 0.05), snappedf(p.z, 0.05))
					_rebuild_building(_sel)
					_pave_dirty = 0.35
			"orbit":
				cam["yaw"] = clampf(float(cam["yaw"]) - mm.relative.x * 0.25, -60.0, 60.0)
				cam["pitch"] = clampf(float(cam["pitch"]) + mm.relative.y * 0.2, 15.0, 85.0)
				_sync_sliders()
			"pan":
				var k := float(cam["dist"]) * tan(deg_to_rad(float(cam["fov"]) / 2.0)) / 360.0
				var yaw := deg_to_rad(float(cam["yaw"]))
				var d := Vector2(-mm.relative.x, -mm.relative.y) * k * 2.0
				cam["cx"] = clampf(float(cam["cx"]) + d.x * cos(yaw) + d.y * sin(yaw), -8.0, 8.0)
				cam["cz"] = clampf(float(cam["cz"]) - d.x * sin(yaw) + d.y * cos(yaw), -8.0, 8.0)
				_sync_sliders()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q or event.keycode == KEY_E:
			_buildings[_sel]["rot"] += deg_to_rad(5.0 if event.keycode == KEY_Q else -5.0)
			_rebuild_building(_sel)
			_pave_dirty = 0.35
