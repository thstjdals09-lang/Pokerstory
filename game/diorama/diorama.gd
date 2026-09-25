extends Node3D
## 3D diorama prototype of the village square, built only from primitive shapes (no image assets).
## Layout comes from the same data as the 2D square (data/locations.json, 100 px = 1 m; x -> X,
## y -> Z, fronts face +Z toward the camera). The 2D game is untouched; run with
## run_diorama.bat (Forward+ renderer). Keys: WASD / arrows walk, T day <-> evening, Esc quit.
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


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.get_slice("=", 1)
		if a == "--evening":
			_evening = true
	var loc: Dictionary = Game.data.locations["village_square"]
	_build_world_env()
	_build_ground(loc)
	for b in loc["buildings"]:
		_build_building(b)
	for g in loc["gates"]:
		_gate(_v(g["pos"]) + Vector3(0, 0, 0.1))
	_build_decor(loc)
	_build_people()
	_build_camera()
	_build_hud()
	_apply_time()
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
	_sun.directional_shadow_max_distance = 40.0
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
	else:
		_sun.light_color = Color("#ffe2b5")
		_sun.light_energy = 1.05
		sm.sky_top_color = Color("#8fb6e8")
		sm.sky_horizon_color = Color("#f2dcb8")
		sm.ground_horizon_color = Color("#b9a27a")
		_env.ambient_light_energy = 0.55
		_env.glow_intensity = 0.3
	for l in _night_lights:
		l.visible = _evening
	for g in _glows:
		g[0].emission_energy_multiplier = g[2] if _evening else g[1]
	if _hud_loc != null:
		_hud_icon.texture = ArtLib.texture("ui.moon" if _evening else "ui.sun")


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = 30.0
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 20.0
	attrs.dof_blur_far_transition = 9.0
	attrs.dof_blur_near_enabled = true
	attrs.dof_blur_near_distance = 12.5
	attrs.dof_blur_near_transition = 4.0
	attrs.dof_blur_amount = 0.09
	_cam.attributes = attrs
	add_child(_cam)
	_cam.current = true
	_follow(1.0)


## The camera looks down at about 40 degrees from the south, following the player softly.
func _follow(weight: float) -> void:
	var focus := _player.position
	focus.x = clampf(focus.x, 5.0, 11.0)
	focus.z = clampf(focus.z, 3.8, 8.0)
	var want := focus + Vector3(0, 11.0, 13.0)
	_cam.position = _cam.position.lerp(want, weight)
	_cam.look_at(_cam.position - Vector3(0, 11.0, 13.0), Vector3.UP)


# --- ground --------------------------------------------------------------------------------------

func _build_ground(loc: Dictionary) -> void:
	var size := _v(loc["size"])
	var grass := StandardMaterial3D.new()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var nt := NoiseTexture2D.new()
	nt.noise = noise
	nt.seamless = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color("#6f8f3e"))
	ramp.set_color(1, Color("#9bbb55"))
	nt.color_ramp = ramp
	grass.albedo_texture = nt
	grass.uv1_scale = Vector3(6, 6, 6)
	grass.roughness = 0.95
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size.x + 20.0, size.z + 20.0)
	g.mesh = pm
	g.material_override = grass
	g.position = Vector3(size.x / 2.0, 0, size.z / 2.0)
	add_child(g)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(cs)
	add_child(floor_body)
	# Edges of the walkable square.
	_solid_box(Vector3(size.x / 2.0, 1, -0.5), Vector3(size.x + 2, 2, 1))
	_solid_box(Vector3(size.x / 2.0, 1, size.z + 0.5), Vector3(size.x + 2, 2, 1))
	_solid_box(Vector3(-0.5, 1, size.z / 2.0), Vector3(1, 2, size.z + 2))
	_solid_box(Vector3(size.x + 0.5, 1, size.z / 2.0), Vector3(1, 2, size.z + 2))
	# Cobblestones: flat rounded stones on the paths, concentric rings on the plaza.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var stones: Array = []
	for p in loc["paths"]:
		var r := Rect2(float(p[0]) * PX, float(p[1]) * PX, float(p[2]) * PX, float(p[3]) * PX)
		var y := r.position.y + 0.1
		while y < r.end.y:
			var x := r.position.x + 0.1 + (0.08 if int(y * 10) % 2 == 0 else 0.0)
			while x < r.end.x:
				var c := Vector2(x + rng.randf_range(-0.03, 0.03), y + rng.randf_range(-0.03, 0.03))
				if c.distance_to(Vector2(8.0, 5.6)) > 1.72:
					stones.append([c, rng.randf_range(0.075, 0.1)])
				x += 0.18
			y += 0.17
	var plaza := Vector2(8.0, 5.6)
	var ring := 0.35
	while ring < 1.75:
		var n := int(TAU * ring / 0.2)
		for i in n:
			var a := TAU * (i + rng.randf() * 0.2) / n
			stones.append([plaza + Vector2(cos(a), sin(a)) * ring, rng.randf_range(0.085, 0.11)])
		ring += 0.2
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
	var sand := [Color("#d9c09a"), Color("#cdb088"), Color("#e4cfa8"), Color("#bfa37e"), Color("#d6bd97")]
	for i in stones.size():
		var s: Array = stones[i]
		var c: Vector2 = s[0]
		var rad: float = s[1]
		var t := Transform3D(Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rad * rng.randf_range(1.0, 1.3), 0.15, rad)), Vector3(c.x, 0.02, c.y))
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, sand[rng.randi() % sand.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	# Mortar under the stones so gaps read as paving, not grass.
	var mortar := _mat(Color("#9c8a6e"))
	for p in loc["paths"]:
		_box(self, Vector3(float(p[2]) * PX, 0.01, float(p[3]) * PX), Vector3((float(p[0]) + float(p[2]) / 2.0) * PX, 0.005, (float(p[1]) + float(p[3]) / 2.0) * PX), mortar)
	_cyl(self, 1.75, 1.75, 0.01, Vector3(8.0, 0.005, 5.6), mortar, 48)
	# Grass tufts and wildflowers scattered on the lawn.
	_scatter_grass(size, rng, loc)


func _scatter_grass(size: Vector3, rng: RandomNumberGenerator, loc: Dictionary) -> void:
	var blocked: Array = []
	for p in loc["paths"]:
		blocked.append(Rect2(float(p[0]) * PX - 0.1, float(p[1]) * PX - 0.1, float(p[2]) * PX + 0.2, float(p[3]) * PX + 0.2))
	for b in loc["buildings"]:
		var r: Array = b["rect"]
		blocked.append(Rect2(float(r[0]) * PX, float(r[1]) * PX, float(r[2]) * PX, float(r[3]) * PX))
	var on_lawn := func(c: Vector2) -> bool:
		if c.distance_to(Vector2(8.0, 5.6)) < 1.9:
			return false
		for r in blocked:
			if r.has_point(c):
				return false
		return true
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
	for i in 2600:
		var c := Vector2(rng.randf() * size.x, rng.randf() * size.z)
		if on_lawn.call(c):
			pts.append(c)
	tuft.instance_count = pts.size()
	for i in pts.size():
		var c: Vector2 = pts[i]
		tuft.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.7, 1.4)), Vector3(c.x, 0.07, c.y)))
		tuft.set_instance_color(i, Color("#5f8a34").lerp(Color("#a9c65a"), rng.randf()))
	var ti := MultiMeshInstance3D.new()
	ti.multimesh = tuft
	add_child(ti)
	var flowers := MultiMesh.new()
	flowers.transform_format = MultiMesh.TRANSFORM_3D
	flowers.use_colors = true
	var bud := SphereMesh.new()
	bud.radius = 0.035
	bud.height = 0.05
	bud.radial_segments = 6
	bud.rings = 3
	var fm := _mat(Color.WHITE, 0.7)
	fm.vertex_color_use_as_albedo = true
	bud.material = fm
	flowers.mesh = bud
	var fpts: Array = []
	for _cluster in 70:
		var c := Vector2(rng.randf() * size.x, rng.randf() * size.z)
		if not on_lawn.call(c):
			continue
		var col: Color = [Color("#fff4e0"), Color("#f7c6d9"), Color("#ffd75e"), Color("#b79be8")][rng.randi() % 4]
		for i in 7:
			fpts.append([c + Vector2(rng.randf_range(-0.18, 0.18), rng.randf_range(-0.18, 0.18)), col])
	flowers.instance_count = fpts.size()
	for i in fpts.size():
		var f: Array = fpts[i]
		var c: Vector2 = f[0]
		flowers.set_instance_transform(i, Transform3D(Basis(), Vector3(c.x, 0.1, c.y)))
		flowers.set_instance_color(i, f[1])
	var fi := MultiMeshInstance3D.new()
	fi.multimesh = flowers
	add_child(fi)


# --- buildings -----------------------------------------------------------------------------------

const STYLES := {
	"shop_building": {"wall": "#efe0c4", "roof": "#c9573f", "trim": "#6b4428", "h": 2.4, "floors": 2},
	"home_building": {"wall": "#f1e6cf", "roof": "#6f9450", "trim": "#6b4428", "h": 2.0, "floors": 1},
	"card_room_building": {"wall": "#d8ccb6", "roof": "#35507a", "trim": "#5a3a24", "h": 2.6, "floors": 2},
	"community_hall_building": {"wall": "#e9dcc2", "roof": "#7a5a9a", "trim": "#6b4c30", "h": 2.2, "floors": 1},
}


func _build_building(b: Dictionary) -> void:
	var st: Dictionary = STYLES.get(b["id"], STYLES["home_building"])
	var r: Array = b["rect"]
	var w := float(r[2]) * PX
	var d := float(r[3]) * PX * 0.9
	var front := (float(r[1]) + float(r[3])) * PX
	var cx := (float(r[0]) + float(r[2]) / 2.0) * PX
	var base := Vector3(cx, 0, front - d / 2.0)
	var root := Node3D.new()
	root.position = base
	add_child(root)
	_solid_box(base + Vector3(0, 1, 0), Vector3(w, 2, d))
	var h: float = st["h"]
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
	var dx := float(b["door"][0]) * PX - cx
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
	spill.position = root.position + Vector3(0, 1.2, d / 2.0 + 0.9)
	add_child(spill)
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
	l.position = (parent.position if parent != self else Vector3.ZERO) + at
	add_child(l)
	_night_lights.append(l)


# --- props ---------------------------------------------------------------------------------------

func _build_decor(loc: Dictionary) -> void:
	for d in loc["decor"]:
		if d.has("conditions") and not Conditions.check(d["conditions"], Game.state if Game.state != null else GameState.new(), "village_square"):
			continue
		var at: Vector3 = _v(d.get("art_pos", d.get("pos", [0, 0])))
		if d.has("rect") and not d.has("art_pos"):
			var r: Array = d["rect"]
			at = Vector3((float(r[0]) + float(r[2]) / 2.0) * PX, 0, (float(r[1]) + float(r[3])) * PX)
		match str(d.get("art", d.get("type", ""))):
			"sq.fountain":
				_fountain(at)
			"sq.tree":
				_tree(at, Color("#6f9a45"))
			"sq.tree_blossom":
				_tree(at, Color("#f2b8c8"))
			"sq.bush":
				_bush(at)
			"sq.planter":
				_planter(at)
			"sq.lamp":
				_lamp(at)
			"sq.bench":
				_bench(at)
			"sq.board":
				_board(at)
			"sq.booth":
				_booth(at)
			"sq.crates":
				_crates(at)
			"sq.pot":
				_pot(at)
	for it in loc["interactables"]:
		if str(it.get("art", "")) == "sq.aframe":
			_aframe(_v(it["pos"]))
	for s in loc.get("signs", []):
		_signpost(_v(s["pos"]))


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


func _tree(at: Vector3, leaf: Color) -> void:
	_cyl(self, 0.1, 0.14, 1.0, at + Vector3(0, 0.5, 0), _mat(Color("#6b4a30")))
	var m := _mat(leaf)
	var m2 := _mat(leaf.darkened(0.12))
	_ball(self, 0.62, at + Vector3(0, 1.35, 0), m)
	_ball(self, 0.45, at + Vector3(-0.38, 1.15, 0.12), m2)
	_ball(self, 0.45, at + Vector3(0.38, 1.2, -0.05), m2)
	_ball(self, 0.4, at + Vector3(0.05, 1.75, 0.05), m)
	_solid_round(at, 0.25)


func _bush(at: Vector3) -> void:
	var m := _mat(Color("#5f8f3c"))
	_ball(self, 0.26, at + Vector3(0, 0.2, 0), m, Vector3(1, 0.8, 1))
	_ball(self, 0.2, at + Vector3(0.2, 0.16, 0.05), m, Vector3(1, 0.8, 1))
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
	_cyl(self, 0.04, 0.06, 1.3, at + Vector3(0, 0.65, 0), iron, 8)
	_cyl(self, 0.1, 0.12, 0.08, at + Vector3(0, 0.04, 0), iron, 8)
	_lantern(self, at + Vector3(0, 1.42, 0))
	_solid_round(at, 0.08)


func _bench(at: Vector3) -> void:
	var wood := _mat(Color("#8a5a36"))
	_box(self, Vector3(0.8, 0.06, 0.28), at + Vector3(0, 0.32, 0), wood)
	_box(self, Vector3(0.8, 0.22, 0.05), at + Vector3(0, 0.5, -0.14), wood)
	for x in [-0.34, 0.34]:
		_box(self, Vector3(0.05, 0.32, 0.26), at + Vector3(x, 0.16, 0), _mat(Color("#2a2522")))


func _board(at: Vector3) -> void:
	var wood := _mat(Color("#7a5230"))
	for x in [-0.36, 0.36]:
		_box(self, Vector3(0.08, 1.3, 0.08), at + Vector3(x, 0.65, 0), wood)
	_box(self, Vector3(0.9, 0.6, 0.06), at + Vector3(0, 0.95, 0), _mat(Color("#9c6b42")))
	_prism(self, Vector3(1.05, 0.18, 0.25), at + Vector3(0, 1.36, 0), _mat(Color("#5f7a4a")))
	for i in 4:
		_box(self, Vector3(0.16, 0.2, 0.01), at + Vector3(-0.3 + i * 0.2, 0.95 + (0.08 if i % 2 == 0 else -0.06), 0.04), _mat(Color("#fbf1dc")))
	_solid_box(at + Vector3(0, 1, 0), Vector3(0.9, 2, 0.2))


func _booth(at: Vector3) -> void:
	var wood := _mat(Color("#8a5a36"))
	_box(self, Vector3(1.2, 0.7, 0.5), at + Vector3(0, 0.35, 0), wood)
	for x in [-0.55, 0.55]:
		_box(self, Vector3(0.07, 1.5, 0.07), at + Vector3(x, 0.75, 0.2), wood)
	for i in 6:
		var a := _box(self, Vector3(0.2, 0.05, 0.7), at + Vector3(-0.5 + i * 0.2, 1.45, 0.1), _mat(Color("#3f7f7a") if i % 2 == 0 else Color("#f3e6cc")))
		a.rotation.x = 0.35
	for i in 5:
		_ball(self, 0.08, at + Vector3(-0.4 + i * 0.2, 0.76, 0.1), _mat([Color("#e8894a"), Color("#c9473f"), Color("#ffd75e")][i % 3]))
	_solid_box(at + Vector3(0, 1, 0), Vector3(1.2, 2, 0.5))


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
	_player.position = Vector3(8.0, 0, 7.6)
	add_child(_player)
	_player_body = _person(_player, Color("#d9a441"), Color("#6b3f24"), Color("#3f7f7a"))
	var places := {"npc_lumi": "fox", "npc_moa": "fairy", "npc_juno": "bird"}
	for id in places:
		var place: Dictionary = Game.data.npc_place(id, "evening" if _evening else "day", Game.state if Game.state != null else GameState.new())
		if str(place.get("loc", "")) != "village_square":
			continue
		var node := Node3D.new()
		node.position = _v(place["pos"])
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
	var hint := UiKit.label("3D 시안 · WASD 이동 · T 낮/저녁 · Esc 종료", 14, Color(1, 1, 1, 0.85))
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
	_follow(clampf(delta * 5.0, 0.0, 1.0))
	if _lumi != null:
		_prompt.visible = _player.position.distance_to(_lumi.position) < 1.3


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
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
