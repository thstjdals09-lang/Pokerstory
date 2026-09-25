extends Control
## One playing card on screen. Face-down cards hold no card data at all (card == null),
## so the UI cannot leak the opponent's hidden hand.

signal pressed(index: int)

const CARD_SIZE := Vector2(104, 148)
const LIFT := 26.0
const UI_FONT := preload("res://assets/fonts/ui_font.tres")
const INK := Color("#2b2320")
const RED := Color("#c0392b")

var index := 0
var card: Card = null
var selected := false
var interactive := false
## Reserve room above the card so a selected card can rise. Off for the opponent's row.
var lift_space := true:
	set(value):
		lift_space = value
		custom_minimum_size = CARD_SIZE + (Vector2(0, LIFT) if value else Vector2.ZERO)
		queue_redraw()
var _hover := false


func _init() -> void:
	custom_minimum_size = CARD_SIZE + Vector2(0, LIFT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


## lucky_mark: a small star on a card the player locked.
var marked := false


func show_card(c: Card) -> void:
	card = c
	queue_redraw()


func show_back() -> void:
	card = null
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func _set_hover(value: bool) -> void:
	_hover = value
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if interactive and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(index)
		accept_event()


func _draw() -> void:
	var top := 0.0 if (selected or not lift_space) else LIFT
	var r := Rect2(Vector2(0, top), CARD_SIZE)
	draw_rect(Rect2(r.position + Vector2(4, 6), r.size), Color(0, 0, 0, 0.25))
	if card == null:
		_draw_back(r)
		return
	var border := UiKit.GOLD if selected else Color("#b08a66")
	draw_style_box(UiKit.stylebox(Color("#fffaf0"), border, 5 if selected else 2, 10, 0), r)
	draw_style_box(UiKit.stylebox(Color(0, 0, 0, 0), Color("#eadbc4"), 1, 6, 0), r.grow(-6))
	var col := RED if card.is_red() else INK
	_draw_index(r.position + Vector2(10, 24), col)
	# the same index upside down in the far corner
	draw_set_transform(r.end, PI, Vector2.ONE)
	_draw_index(Vector2(10, 24), col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var rank := card.rank_label()
	if rank in ["J", "Q", "K"]:
		var frame := Rect2(r.position + Vector2(32, 30), r.size - Vector2(64, 60))
		draw_style_box(UiKit.stylebox(Color("#fbe9e4") if card.is_red() else Color("#e7ecf3"), Color(col, 0.6), 2, 6, 0), frame)
		draw_string(UI_FONT, Vector2(frame.position.x, frame.position.y + 44), rank, HORIZONTAL_ALIGNMENT_CENTER, frame.size.x, 36, col)
		draw_string(UI_FONT, Vector2(frame.position.x, frame.end.y - 10), card.suit_symbol(), HORIZONTAL_ALIGNMENT_CENTER, frame.size.x, 28, col)
	else:
		var big := 64 if rank == "A" else 50
		draw_string(UI_FONT, Vector2(r.position.x, r.position.y + 92 + (6 if rank == "A" else 0)), card.suit_symbol(), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, big, col)
	if marked:
		draw_circle(Vector2(r.end.x - 14, r.position.y + 14), 9, UiKit.GOLD)
		draw_string(UI_FONT, Vector2(r.end.x - 23, r.position.y + 20), "★", HORIZONTAL_ALIGNMENT_CENTER, 18, 14, INK)
	if selected:
		var tag := Rect2(r.position.x + 14, r.end.y - 30, r.size.x - 28, 22)
		draw_rect(tag, UiKit.GOLD)
		draw_string(UI_FONT, Vector2(tag.position.x, tag.end.y - 5), "교체", HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 15, INK)
	elif _hover and interactive:
		draw_rect(r.grow(2), UiKit.ACCENT, false, 3.0)


func _draw_index(at: Vector2, col: Color) -> void:
	draw_string(UI_FONT, at, card.rank_label(), HORIZONTAL_ALIGNMENT_CENTER, 22, 21, col)
	draw_string(UI_FONT, at + Vector2(0, 19), card.suit_symbol(), HORIZONTAL_ALIGNMENT_CENTER, 22, 16, col)


## Card back: the equipped colour, a cream frame, a faint diamond lattice and a club medallion.
func _draw_back(r: Rect2) -> void:
	var back := Color("#2e4a74")
	if Game.state != null and Game.state.equipped.has("card_back"):
		back = Game.item_color(str(Game.state.equipped["card_back"]), back)
	draw_style_box(UiKit.stylebox(back, Color("#f3dfc1"), 4, 10, 0), r)
	var inner := r.grow(-11)
	draw_style_box(UiKit.stylebox(Color(0, 0, 0, 0), Color("#f3dfc1"), 1, 5, 0), inner)
	var step := 14.0
	var y := inner.position.y + step / 2.0
	var row := 0
	while y < inner.end.y:
		var x := inner.position.x + (step / 2.0 if row % 2 == 0 else step)
		while x < inner.end.x - 2:
			var d := PackedVector2Array([Vector2(x, y - 4), Vector2(x + 4, y), Vector2(x, y + 4), Vector2(x - 4, y)])
			draw_colored_polygon(d, Color(1, 1, 1, 0.13))
			x += step
		y += step / 2.0
		row += 1
	var c := r.get_center()
	draw_circle(c, 21, back.darkened(0.15))
	draw_arc(c, 21, 0, TAU, 40, Color("#f3dfc1"), 2.0, true)
	draw_string(UI_FONT, c + Vector2(-20, 10), "♣", HORIZONTAL_ALIGNMENT_CENTER, 40, 26, Color("#f3dfc1"))
