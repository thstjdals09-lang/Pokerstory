@tool
extends Marker3D
## One prop of the 3D square (lamp, bench, flower bed, fence...). Move and turn it with the editor
## gizmo (only the Y rotation is used); "size" means: bed = width x depth, fence = length,
## gate = width, tree / bush = scale (x). The diorama rebuilds its preview around it.

@export_enum("lamp", "bench", "board", "bed", "stall", "gate", "fence", "tree", "blossom", "bush", "barrel", "crates", "pot", "aframe", "mailbox")
var kind := "lamp":
	set(v):
		kind = v
		_poke()
@export var size := Vector2.ONE:
	set(v):
		size = v
		_poke()


func _ready() -> void:
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_poke()


func _poke() -> void:
	if Engine.is_editor_hint() and is_inside_tree() and owner != null and owner.has_method("queue_rebuild"):
		owner.queue_rebuild()


func to_prop() -> Dictionary:
	return {"kind": kind, "at": Vector3(position.x, 0.0, position.z), "rot": rotation.y, "size": size}
