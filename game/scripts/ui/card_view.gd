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
		var back := Color("#2e4a74")
		if Game.state != null and Game.state.equipped.has("card_back"):
			back = Game.item_color(str(Game.state.equipped["card_back"]), back)
		draw_style_box(UiKit.stylebox(back, Color("#f3dfc1"), 4, 10, 0), r)
		var inner := r.grow(-12)
		draw_rect(inner, Color("#f3dfc1"), false, 2.0)
		var y := inner.position.y + 10
		while y < inner.end.y - 6:
			draw_string(UI_FONT, Vector2(inner.position.x, y + 12), "◆ ◆ ◆", HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 14, Color(1, 1, 1, 0.25))
			y += 22
		return
	var border := UiKit.GOLD if selected else Color("#8a5a3c")
	draw_style_box(UiKit.stylebox(Color("#fffdf8"), border, 5 if selected else 2, 10, 0), r)
	var col := RED if card.is_red() else INK
	var corner := "%s\n%s" % [card.rank_label(), card.suit_symbol()]
	draw_multiline_string(UI_FONT, r.position + Vector2(9, 26), corner, HORIZONTAL_ALIGNMENT_LEFT, 40, 22, 2, col)
	draw_string(UI_FONT, Vector2(r.position.x, r.position.y + 100), card.suit_symbol(), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 54, col)
	if selected:
		var tag := Rect2(r.position.x + 14, r.end.y - 30, r.size.x - 28, 22)
		draw_rect(tag, UiKit.GOLD)
		draw_string(UI_FONT, Vector2(tag.position.x, tag.end.y - 5), "교체", HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 15, INK)
	elif _hover and interactive:
		draw_rect(r.grow(2), UiKit.ACCENT, false, 3.0)
