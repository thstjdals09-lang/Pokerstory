class_name Geo
extends RefCounted
## Converts JSON arrays from data files into Godot geometry types.


static func vec(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func rect(a) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
