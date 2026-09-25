extends CharacterBody2D
## The player avatar: top-down movement with collision. Interaction is resolved by World.

const SPEED := 230.0
const RADIUS := 14.0
const BODY_COLOR := Color("#3a7bd5")

var input_enabled := true
var facing := Vector2.DOWN
var _name_label: Label


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)
	_name_label = WorldLabel.make("", 14, Color.WHITE)
	_name_label.position = Vector2(-70, -46)
	_name_label.size = Vector2(140, 20)
	add_child(_name_label)


func set_display_name(text: String) -> void:
	_name_label.text = text


func _physics_process(_delta: float) -> void:
	var dir := Vector2.ZERO
	if input_enabled:
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED
	if dir != Vector2.ZERO:
		facing = dir.normalized()
		queue_redraw()
	move_and_slide()


func _draw() -> void:
	draw_circle(Vector2(0, 11), RADIUS * 0.9, Color(0, 0, 0, 0.2))
	draw_circle(Vector2.ZERO, RADIUS + 3, Color.WHITE)
	draw_circle(Vector2.ZERO, RADIUS, BODY_COLOR)
	# Equipped clothing shows as a coloured coat band (placeholder art).
	var cloth := str(Game.state.equipped.get("clothing", "")) if Game.state != null else ""
	if cloth != "":
		draw_arc(Vector2.ZERO, RADIUS - 4, 0.2 * PI, 0.8 * PI, 16, Game.item_color(cloth, BODY_COLOR), 7.0)
	var tip := facing * (RADIUS + 8)
	var side := facing.orthogonal() * 6
	var base := facing * RADIUS * 0.55
	draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), Color.WHITE)
