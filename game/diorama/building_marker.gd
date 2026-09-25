@tool
extends Marker3D
## One building of the 3D square. Move and turn it with the editor gizmo (only the Y rotation is
## used) and set its size in the Inspector; the diorama rebuilds its preview around it.

@export var building_id := "home_building":
	set(v):
		building_id = v
		_poke()
@export_range(1.5, 8.0, 0.05) var width := 3.2:
	set(v):
		width = v
		_poke()
@export_range(1.5, 8.0, 0.05) var depth := 2.4:
	set(v):
		depth = v
		_poke()
@export_range(1.2, 5.0, 0.05) var wall_height := 2.0:
	set(v):
		wall_height = v
		_poke()
## Door position along the front, from the middle (metres).
@export_range(-3.0, 3.0, 0.05) var door_offset := 0.0:
	set(v):
		door_offset = v
		_poke()


func _ready() -> void:
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_poke()


func _poke() -> void:
	if Engine.is_editor_hint() and is_inside_tree() and owner != null and owner.has_method("queue_rebuild"):
		owner.queue_rebuild()


func to_layout() -> Dictionary:
	return {"id": building_id, "at": Vector2(position.x, position.z), "rot": rotation.y, "w": width, "d": depth,
		"h": wall_height, "door": door_offset, "marker": self}


func from_layout(b: Dictionary) -> void:
	position = Vector3(b["at"].x, 0.0, b["at"].y)
	rotation = Vector3(0.0, b["rot"], 0.0)
	width = b["w"]
	depth = b["d"]
	wall_height = b["h"]
	door_offset = b["door"]
