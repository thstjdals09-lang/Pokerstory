@tool
extends Node3D
## The 3D game camera (run_diorama.bat). Open scenes/game_camera_3d.tscn (edit_camera3d.bat), select
## this root node and change the values in the Inspector; the game reads them when it starts.
## The viewport shows a real place built by the game's own 3D view code. Drag the "Player" marker to
## where the player stands, select "Camera3D" and tick Preview to see exactly the game's frame.
## "preview_talk" shows the talk camera between "Player" and "Resident".

@export_enum("village_square", "residential", "market", "grove", "waterfront", "player_home", "card_room",
	"small_shop", "player_home_annex", "player_home_hall", "community_hall", "tailor", "tea_house", "workshop",
	"guest_cottage") var preview_location := "village_square"
@export var preview_evening := false
## Show the talk camera between the Player and Resident markers.
@export var preview_talk := false

@export_group("Camera")
## Distance from the player (metres).
@export_range(3.0, 80.0, 0.01) var cam_distance := 31.03
## Zoom: field of view in degrees (smaller = closer, flatter).
@export_range(6.0, 70.0, 0.1) var cam_fov := 20.0
## How far it looks down (degrees).
@export_range(5.0, 85.0, 0.1) var cam_pitch := 20.5
## Turn left/right (degrees).
@export_range(-60.0, 60.0, 0.1) var cam_yaw := 0.0
## Indoors the camera comes this much closer (rooms are smaller than the square).
@export_range(0.3, 1.5, 0.01) var interior_zoom := 0.8

@export_group("Blur")
@export var blur_on := true
@export_range(0.0, 0.3, 0.005) var blur_amount := 0.05
## Blur starts this many metres in front of the player.
@export_range(0.5, 40.0, 0.1) var blur_near_start := 8.6
## Blur starts this many metres behind the player.
@export_range(0.5, 60.0, 0.1) var blur_far_start := 11.9
@export_range(0.1, 30.0, 0.1) var blur_softness := 5.0

@export_group("Talk camera")
@export_range(2.0, 15.0, 0.1) var talk_distance := 9.0
@export_range(10.0, 70.0, 0.5) var talk_fov := 30.0
@export_range(5.0, 60.0, 0.5) var talk_pitch := 17.0
## How far the view turns to the side of the pair (0 = from the front, 1 = full side).
@export_range(0.0, 1.0, 0.05) var talk_side := 0.75
## Raises the pair on screen, above the dialogue box.
@export_range(0.0, 2.0, 0.05) var talk_lift := 0.85
## Seconds to glide into and out of a talk.
@export_range(0.1, 3.0, 0.05) var talk_glide := 0.8

const SETTINGS := ["cam_fov", "cam_pitch", "cam_yaw", "interior_zoom", "blur_on", "blur_amount", "blur_near_start",
	"blur_far_start", "blur_softness", "talk_distance", "talk_fov", "talk_pitch", "talk_side", "talk_lift", "talk_glide"]

var _view: Node3D
var _built := ""
var _locations := {}
var _built_once := false


## A new place: the Player marker goes to its start point, the Resident next to it.
func _to_spawn(loc: Dictionary) -> void:
	var sp: Array = loc.get("spawns", {}).get("default", [0, 0])
	var at := Vector3(float(sp[0]) * 0.01, 0, float(sp[1]) * 0.01)
	var player := get_node_or_null("Player") as Node3D
	var resident := get_node_or_null("Resident") as Node3D
	if player != null:
		player.position = at
	if resident != null:
		resident.position = at + Vector3(1.0, 0, -0.8)
	_view._talk_hidden.clear()


## Figures on the markers (preview only, not saved in the scene).
func _add_figures() -> void:
	for pair in [["Player", Color("#3a7bd5")], ["Resident", Color("#e8894a")]]:
		var m := get_node_or_null(pair[0]) as Node3D
		if m == null or m.has_node("_figure"):
			continue
		var fig: Node3D = _view._figure(m, pair[1], Color("#f6d7bd"), 1.0)
		fig.name = "_figure"


func _process(_delta: float) -> void:
	if _view == null:
		_view = load("res://scripts/world3d/view3d.gd").new()
		_view.preview = true
		add_child(_view)
	var loc: Dictionary = _location()
	if loc.is_empty():
		return
	var key := "%s|%s" % [preview_location, preview_evening]
	if key != _built:
		var moved := _built.get_slice("|", 0) != preview_location
		_built = key
		_view.build_preview(preview_location, loc, preview_evening)
		var player_now := get_node_or_null("Player") as Node3D
		var size: Array = loc.get("size", [0, 0])
		var outside := player_now != null and not Rect2(0, 0, float(size[0]) * 0.01, float(size[1]) * 0.01).has_point(
			Vector2(player_now.position.x, player_now.position.z))
		if (moved and _built_once) or outside:
			_to_spawn(loc)
		_built_once = true
		_add_figures()
	for k in SETTINGS:
		_view.set(k, get(k))
	_view.cam_dist = cam_distance
	var cam := get_node_or_null("Camera3D") as Camera3D
	var player := get_node_or_null("Player") as Node3D
	if cam == null or player == null:
		return
	_view._cam = cam
	var interior: bool = loc.get("interior", false)
	var resident := get_node_or_null("Resident") as Node3D
	# what blocks the talk view is hidden while previewing it, as in the game
	for n in _view._talk_hidden:
		if is_instance_valid(n):
			n.visible = true
	_view._talk_hidden.clear()
	if preview_talk and resident != null:
		cam.transform = _view._talk_shot(player.position, resident.position, interior)
		_view._hide_blockers(cam.transform.origin, (player.position + resident.position) / 2.0 + Vector3(0, 0.5, 0))
		cam.fov = talk_fov
		_view._apply_blur(talk_distance)
	else:
		cam.transform = _view.follow_xf(player.position, interior)
		cam.fov = cam_fov
		_view._apply_blur(cam_distance * (interior_zoom if interior else 1.0))


func _location() -> Dictionary:
	if _locations.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/locations.json"))
		if parsed is Dictionary:
			_locations = parsed.get("locations", {})
	return _locations.get(preview_location, {})
