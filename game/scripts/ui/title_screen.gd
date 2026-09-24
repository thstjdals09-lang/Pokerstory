extends Control
## Title: new game (with name entry and overwrite confirmation), continue, quit.

signal new_game_requested(player_name: String)
signal continue_requested
signal quit_requested

const UI_FONT := preload("res://assets/fonts/ui_font.tres")

var new_game_button: Button
var continue_button: Button
var quit_button: Button
var name_edit: LineEdit
var start_button: Button
var overwrite_yes_button: Button
var _main_box: VBoxContainer
var _name_panel: PanelContainer
var _confirm_panel: PanelContainer
var _message: Label
var _has_save := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	add_child(UiKit.centered(col))

	var title := UiKit.label("Pokerstory", 64, Color("#fff3d6"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color("#3b2a20"))
	col.add_child(title)
	var sub := UiKit.label("가제 · Project 20 첫 플레이 프로토타입", 18, Color("#f3dfc1"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	col.add_child(spacer)

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 10)
	col.add_child(_main_box)
	new_game_button = UiKit.button("새 게임", 260)
	continue_button = UiKit.button("이어하기", 260)
	quit_button = UiKit.button("종료", 260)
	for b in [new_game_button, continue_button, quit_button]:
		_main_box.add_child(b)
	new_game_button.pressed.connect(_on_new_game)
	continue_button.pressed.connect(func(): continue_requested.emit())
	quit_button.pressed.connect(func(): quit_requested.emit())

	_message = UiKit.wrap_label("", 16, Color("#ffd6c9"))
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.custom_minimum_size = Vector2(520, 0)
	col.add_child(_message)

	# name entry
	_name_panel = UiKit.panel()
	var nb := VBoxContainer.new()
	nb.add_theme_constant_override("separation", 10)
	_name_panel.add_child(nb)
	nb.add_child(UiKit.label("이름을 알려 주세요", 22))
	name_edit = LineEdit.new()
	name_edit.text = Game.DEFAULT_PLAYER_NAME
	name_edit.max_length = 12
	name_edit.custom_minimum_size = Vector2(320, 44)
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.text_submitted.connect(func(_t): _on_start())
	nb.add_child(name_edit)
	nb.add_child(UiKit.label("비워 두면 '%s'(으)로 시작해요." % Game.DEFAULT_PLAYER_NAME, 14, UiKit.MUTED))
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 10)
	nb.add_child(nrow)
	start_button = UiKit.button("시작하기", 150)
	start_button.pressed.connect(_on_start)
	var back := UiKit.button("뒤로", 150)
	back.pressed.connect(_show_main)
	nrow.add_child(start_button)
	nrow.add_child(back)
	col.add_child(_name_panel)

	# overwrite confirmation
	_confirm_panel = UiKit.panel()
	var cb := VBoxContainer.new()
	cb.add_theme_constant_override("separation", 10)
	_confirm_panel.add_child(cb)
	cb.add_child(UiKit.label("저장된 게임이 있어요. 새로 시작하면 덮어써요.", 18))
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 10)
	cb.add_child(crow)
	overwrite_yes_button = UiKit.button("새로 시작", 150)
	overwrite_yes_button.pressed.connect(_show_name_entry)
	var cancel := UiKit.button("취소", 150)
	cancel.pressed.connect(_show_main)
	crow.add_child(overwrite_yes_button)
	crow.add_child(cancel)
	col.add_child(_confirm_panel)


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color("#35507a"))
	draw_rect(Rect2(0, size.y * 0.62, size.x, size.y * 0.38), Color("#2a3f60"))
	var suits := ["♠", "♥", "♦", "♣"]
	var i := 0
	for y in range(40, int(size.y), 110):
		for x in range(40 + (i % 2) * 55, int(size.x), 110):
			draw_string(UI_FONT, Vector2(x, y), suits[(x / 110 + i) % 4], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.07))
		i += 1


func open(has_save: bool) -> void:
	_has_save = has_save
	visible = true
	_message.text = ""
	_show_main()


func show_message(text: String) -> void:
	_message.text = text


func _show_main() -> void:
	_main_box.visible = true
	_name_panel.visible = false
	_confirm_panel.visible = false
	continue_button.disabled = not _has_save
	new_game_button.grab_focus.call_deferred()


func _on_new_game() -> void:
	_message.text = ""
	if _has_save:
		_main_box.visible = false
		_confirm_panel.visible = true
	else:
		_show_name_entry()


func _show_name_entry() -> void:
	_main_box.visible = false
	_confirm_panel.visible = false
	_name_panel.visible = true
	name_edit.grab_focus.call_deferred()


func _on_start() -> void:
	new_game_requested.emit(name_edit.text)
