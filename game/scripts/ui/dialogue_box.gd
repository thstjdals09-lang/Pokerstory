extends Control
## Bottom dialogue box: speaker name, one line at a time, then choice buttons.
## Advance with E / Enter / click. Choices: click, number keys, or E / Enter on the focused one.
## Esc closes.

signal choice_made(action: String, arg: String)
## Same moment as choice_made, with the whole choice (effects, next entry, ...).
signal choice_picked(choice: Dictionary)
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
## Visual slice: the speaker's name sits on a tab above the box; residents with art show a portrait.
var _name_tab: PanelContainer
var _portrait_frame: PanelContainer
var _portrait: TextureRect


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

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(box)
	var tab_margin := MarginContainer.new()
	tab_margin.add_theme_constant_override("margin_left", 28)
	tab_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tab_margin)
	_name_tab = PanelContainer.new()
	var tab_style := UiKit.dark_style(10, 6)
	tab_style.corner_radius_bottom_left = 0
	tab_style.corner_radius_bottom_right = 0
	tab_style.content_margin_left = 18
	tab_style.content_margin_right = 18
	_name_tab.add_theme_stylebox_override("panel", tab_style)
	_name_tab.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tab_margin.add_child(_name_tab)
	_name_label = UiKit.label("", 19, UiKit.CREAM)
	_name_tab.add_child(_name_label)

	_panel = UiKit.panel(UiKit.PAPER, 18)
	_panel.custom_minimum_size = Vector2(0, 160)
	_panel.gui_input.connect(_on_panel_input)
	box.add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_panel.add_child(row)
	_portrait_frame = PanelContainer.new()
	var frame_style := UiKit.stylebox(Color("#f3dfc1"), UiKit.BORDER, 2, 12, 4)
	_portrait_frame.add_theme_stylebox_override("panel", frame_style)
	_portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_portrait_frame)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(104, 112)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_frame.add_child(_portrait)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(inner)
	_text_label = UiKit.wrap_label("", 21)
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(_text_label)
	_hint_label = UiKit.label("▶ E / Enter / 클릭", 14, UiKit.MUTED)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inner.add_child(_hint_label)
	visible = false


func show_dialogue(speaker: String, lines: Array, choices: Array, portrait_key: String = "") -> void:
	_name_label.text = speaker
	_name_tab.modulate.a = 1.0 if speaker != "" else 0.0
	var face := ArtLib.portrait(portrait_key) if portrait_key != "" else null
	_portrait.texture = face
	_portrait_frame.visible = face != null
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
	choice_picked.emit(c)
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
