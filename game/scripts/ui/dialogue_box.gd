extends Control
## Bottom dialogue box: speaker name, one line at a time, then choice buttons.
## Advance with E / Enter / click. Choices: click, number keys, or E / Enter on the focused one.
## Esc closes.

signal choice_made(action: String, arg: String)
signal closed

var choice_buttons: Array = []
var _lines: Array = []
var _index := 0
var _choices: Array = []
var _name_label: Label
var _text_label: Label
var _hint_label: Label
var _choice_box: VBoxContainer
var _panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 150)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	_choice_box = VBoxContainer.new()
	_choice_box.size_flags_horizontal = Control.SIZE_SHRINK_END
	_choice_box.add_theme_constant_override("separation", 8)
	col.add_child(_choice_box)

	_panel = UiKit.panel(UiKit.PAPER, 18)
	_panel.custom_minimum_size = Vector2(0, 170)
	_panel.gui_input.connect(_on_panel_input)
	col.add_child(_panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	_panel.add_child(inner)
	_name_label = UiKit.label("", 20, UiKit.ACCENT)
	inner.add_child(_name_label)
	_text_label = UiKit.wrap_label("", 21)
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(_text_label)
	_hint_label = UiKit.label("▶ E / Enter / 클릭", 14, UiKit.MUTED)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inner.add_child(_hint_label)
	visible = false


func show_dialogue(speaker: String, lines: Array, choices: Array) -> void:
	_name_label.text = speaker
	_lines = lines if not lines.is_empty() else ["…"]
	_choices = choices
	_index = 0
	visible = true
	_render()


func current_line() -> String:
	return _text_label.text


func showing_choices() -> bool:
	return not choice_buttons.is_empty()


func advance() -> void:
	if showing_choices():
		return
	if _index < _lines.size() - 1:
		_index += 1
		_render()
	else:
		close()


func close() -> void:
	visible = false
	UiKit.clear_children(_choice_box)
	choice_buttons.clear()
	closed.emit()


func pick_choice(i: int) -> void:
	if i < 0 or i >= _choices.size():
		return
	var c: Dictionary = _choices[i]
	visible = false
	UiKit.clear_children(_choice_box)
	choice_buttons.clear()
	choice_made.emit(str(c.get("action", "close")), str(c.get("arg", "")))


func _render() -> void:
	_text_label.text = _lines[_index]
	UiKit.clear_children(_choice_box)
	choice_buttons.clear()
	var last := _index == _lines.size() - 1
	_hint_label.visible = not (last and not _choices.is_empty())
	if last and not _choices.is_empty():
		for i in _choices.size():
			var b := UiKit.button("%d. %s" % [i + 1, _choices[i]["text"]], 300)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(pick_choice.bind(i))
			_choice_box.add_child(b)
			choice_buttons.append(b)
		choice_buttons[0].grab_focus.call_deferred()


func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu"):
		close()
	elif event.is_action_pressed("interact"):
		if showing_choices():
			var focused := get_viewport().gui_get_focus_owner()
			var idx := choice_buttons.find(focused)
			pick_choice(idx if idx >= 0 else 0)
		else:
			advance()
	else:
		for i in 5:
			if event.is_action_pressed("card_%d" % (i + 1)) and showing_choices():
				pick_choice(i)
				break
		return
	get_viewport().set_input_as_handled()
