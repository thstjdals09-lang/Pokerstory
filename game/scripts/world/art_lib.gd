class_name ArtLib
extends RefCounted
## Art registry for the visual slice (data/art.json). Gameplay data names only keys
## ("bld.card_room", "char.lumi"); this maps a key to a texture, its display size, the anchor
## point placed at the data position, optional light points and whether it depth-sorts.
## A key without a readable file simply isn't "has()", and callers fall back to greybox drawing,
## so assets can be swapped or removed without touching scenes or gameplay code.

const REGISTRY := "res://data/art.json"

static var _defs := {}
static var _loaded := false
static var _tex := {}
static var _light_tex: Texture2D = null


static func defs() -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY)) if FileAccess.file_exists(REGISTRY) else null
		_defs = parsed.get("sprites", {}) if parsed is Dictionary else {}
	return _defs


static func has(key: String) -> bool:
	return key != "" and defs().has(key) and texture(key) != null


static func def(key: String) -> Dictionary:
	return defs().get(key, {})


static func texture(key: String) -> Texture2D:
	if _tex.has(key):
		return _tex[key]
	var d: Dictionary = defs().get(key, {})
	var t: Texture2D = null
	if d.has("path") and ResourceLoader.exists(str(d["path"])):
		t = load(str(d["path"]))
	_tex[key] = t
	return t


static func size(key: String) -> Vector2:
	return Geo.vec(def(key).get("size", [0, 0]))


static func anchor(key: String) -> Vector2:
	return Geo.vec(def(key).get("anchor", [0, 0]))


static func sorts(key: String) -> bool:
	return bool(def(key).get("sort", false))


## A character pose: "char.lumi" + "@side1" when that pose exists, else the character itself.
static func pose(key: String, pose_name: String) -> String:
	var k := key + "@" + pose_name
	return k if pose_name != "" and has(k) else key


## A character's dialogue portrait. Painted portraits ("portraits": {mood: path}) come first, with
## "neutral" as the fallback mood; otherwise the "portrait" region [x, y, w, h] of the sprite, in
## source-file px (art is authored at 2x the display size). null without either.
static func portrait(key: String, mood: String = "neutral") -> Texture2D:
	var moods: Dictionary = def(key).get("portraits", {})
	if not moods.is_empty():
		var path := str(moods.get(mood, moods.get("neutral", "")))
		if not _tex.has(path):
			_tex[path] = load(path) if ResourceLoader.exists(path) else null
		return _tex[path]
	var t := texture(key)
	var r: Array = def(key).get("portrait", [])
	if t == null or r.size() != 4:
		return null
	var k := t.get_width() / (size(key).x * 2.0)
	var at := AtlasTexture.new()
	at.atlas = t
	at.region = Rect2(float(r[0]) * k, float(r[1]) * k, float(r[2]) * k, float(r[3]) * k)
	return at


## Draws `key` with its anchor on `pos`. `flip` mirrors it horizontally around the anchor.
static func draw(ci: CanvasItem, key: String, pos: Vector2, scale: float = 1.0, tint: Color = Color.WHITE, flip: bool = false) -> void:
	var t := texture(key)
	if t == null:
		return
	var sz := size(key) * scale
	var an := anchor(key) * scale
	ci.draw_set_transform(pos, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	ci.draw_texture_rect(t, Rect2(-an, sz), false, tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Draws `key` stretched into `rect` (rugs, beds, shelves placed by a data rect).
static func draw_fit(ci: CanvasItem, key: String, rect: Rect2) -> void:
	var t := texture(key)
	if t != null:
		ci.draw_texture_rect(t, rect, false)


## Fills `rect` with a repeating tile at its display size (the node needs texture_repeat on).
static func draw_tiled(ci: CanvasItem, key: String, rect: Rect2) -> void:
	var t := texture(key)
	if t == null:
		return
	var tile := size(key)
	var k := Vector2(t.get_width() / tile.x, t.get_height() / tile.y)
	ci.draw_texture_rect_region(t, rect, Rect2(rect.position * k, rect.size * k))


## A tiled disc (plaza) with the same texture scale.
static func draw_tiled_circle(ci: CanvasItem, key: String, center: Vector2, radius: float) -> void:
	var t := texture(key)
	if t == null:
		return
	var tile := size(key)
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 48:
		var p := center + Vector2.from_angle(TAU * i / 48.0) * radius
		pts.append(p)
		uvs.append(Vector2(p.x / tile.x, p.y / tile.y))
	ci.draw_colored_polygon(pts, Color.WHITE, uvs, t)


## Soft radial texture shared by every light.
static func light_texture() -> Texture2D:
	if _light_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 256
		gt.height = 256
		_light_tex = gt
	return _light_tex


## A warm point light of `radius` px at `pos` (added to `parent`).
static func add_light(parent: Node, pos: Vector2, radius: float, energy: float, color: Color = Color(1.0, 0.7, 0.4)) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = light_texture()
	l.texture_scale = radius / 128.0
	l.position = pos
	l.energy = energy
	l.color = color
	parent.add_child(l)
	return l
