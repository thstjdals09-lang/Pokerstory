extends Control
## Pause menu: resume, collection book, save, back to title, quit (both save first).

signal resume_requested
signal save_requested
signal title_requested
signal quit_requested

const ItemIcon := preload("res://scripts/ui/item_icon.gd")

var resume_button: Button
var collection_button: Button
var save_button: Button
var title_button: Button
var quit_button: Button
var _main: VBoxContainer
var _book: VBoxContainer
var _book_list: VBoxContainer
var _book_title: Label
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UiKit.dim_background())
	var panel := UiKit.panel(UiKit.PAPER, 22)
	panel.custom_minimum_size = Vector2(420, 0)
	add_child(UiKit.centered(panel))
	var holder := VBoxContainer.new()
	panel.add_child(holder)

	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 10)
	holder.add_child(_main)
	_main.add_child(UiKit.label("메뉴", 26, UiKit.ACCENT))
	resume_button = UiKit.button("계속하기", 360)
	collection_button = UiKit.button("수집 도감", 360)
	save_button = UiKit.button("저장하기", 360)
	title_button = UiKit.button("저장하고 타이틀로", 360)
	quit_button = UiKit.button("저장하고 게임 종료", 360)
	for b in [resume_button, collection_button, save_button, title_button, quit_button]:
		_main.add_child(b)
	resume_button.pressed.connect(func(): resume_requested.emit())
	collection_button.pressed.connect(show_collection)
	save_button.pressed.connect(func(): save_requested.emit())
	title_button.pressed.connect(func(): title_requested.emit())
	quit_button.pressed.connect(func(): quit_requested.emit())
	_status = UiKit.label("", 16, UiKit.MUTED)
	_main.add_child(_status)

	_book = VBoxContainer.new()
	_book.add_theme_constant_override("separation", 10)
	holder.add_child(_book)
	_book_title = UiKit.label("", 24, UiKit.ACCENT)
	_book.add_child(_book_title)
	_book_list = VBoxContainer.new()
	_book_list.add_theme_constant_override("separation", 8)
	_book.add_child(_book_list)
	var back := UiKit.button("뒤로", 360)
	back.pressed.connect(show_main)
	_book.add_child(back)
	visible = false


func open() -> void:
	visible = true
	_status.text = ""
	show_main()


func show_main() -> void:
	_main.visible = true
	_book.visible = false
	resume_button.grab_focus.call_deferred()


func set_status(text: String) -> void:
	_status.text = text


func show_collection() -> void:
	_main.visible = false
	_book.visible = true
	UiKit.clear_children(_book_list)
	var found := 0
	for item_id in Game.data.item_order:
		var item: Dictionary = Game.data.items[item_id]
		var known := Game.state.collection.has(item_id)
		found += 1 if known else 0
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var icon := ItemIcon.new()
		icon.setup(item, not known)
		row.add_child(icon)
		var info := VBoxContainer.new()
		info.add_child(UiKit.label(str(item["name"]) if known else "???", 19))
		info.add_child(UiKit.wrap_label(str(item.get("description", "")) if known else "아직 발견하지 못했어요.", 14, UiKit.MUTED))
		info.custom_minimum_size = Vector2(270, 0)
		row.add_child(info)
		_book_list.add_child(row)
	_book_title.text = "수집 도감  %d / %d" % [found, Game.data.item_order.size()]


func collection_text() -> String:
	var parts: Array = [_book_title.text]
	for row in _book_list.get_children():
		for c in row.get_children():
			if c is VBoxContainer:
				parts.append(c.get_child(0).text)
	return " | ".join(parts)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("menu"):
		if _book.visible:
			show_main()
		else:
			resume_requested.emit()
		get_viewport().set_input_as_handled()
