extends Control
## In-world HUD: chip balance, collapsible current goal, location, menu button,
## the context prompt (also clickable, so a touch layer can replace keys later), and toasts.

signal interact_pressed
signal menu_pressed

var _chips_label: Label
var _goal_label: Label
var _goal_toggle: Button
var _goal_collapsed := false
var _location_label: Label
var _prompt_button: Button
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var top_left := UiKit.panel(Color(1, 0.97, 0.91, 0.94), 10)
	top_left.position = Vector2(16, 14)
	add_child(top_left)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	top_left.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	_chips_label = UiKit.label("칩 0", 22, UiKit.TEXT)
	row.add_child(_chips_label)
	_goal_toggle = UiKit.button("목표 접기 (Tab)", 130, false)
	_goal_toggle.custom_minimum_size = Vector2(130, 30)
	_goal_toggle.add_theme_font_size_override("font_size", 14)
	_goal_toggle.pressed.connect(toggle_goal)
	row.add_child(_goal_toggle)
	_goal_label = UiKit.label("", 17, UiKit.ACCENT)
	col.add_child(_goal_label)

	var top_right := HBoxContainer.new()
	top_right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top_right.offset_left = -360
	top_right.offset_right = -16
	top_right.offset_top = 14
	top_right.alignment = BoxContainer.ALIGNMENT_END
	top_right.add_theme_constant_override("separation", 10)
	add_child(top_right)
	var loc_panel := UiKit.panel(Color(1, 0.97, 0.91, 0.94), 8)
	_location_label = UiKit.label("", 17)
	loc_panel.add_child(_location_label)
	top_right.add_child(loc_panel)
	var menu_button := UiKit.button("메뉴 (Esc)", 120, false)
	menu_button.pressed.connect(func(): menu_pressed.emit())
	top_right.add_child(menu_button)

	_prompt_button = UiKit.button("", 260, false)
	_prompt_button.add_theme_font_size_override("font_size", 20)
	_prompt_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_button.offset_left = -170
	_prompt_button.offset_right = 170
	_prompt_button.offset_top = -78
	_prompt_button.offset_bottom = -28
	_prompt_button.visible = false
	_prompt_button.pressed.connect(func(): interact_pressed.emit())
	add_child(_prompt_button)

	_toast_panel = UiKit.panel(Color("#3b2a20"), 12)
	_toast_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast_panel.offset_top = 90
	_toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_label = UiKit.label("", 18, Color("#fff3d6"))
	_toast_panel.add_child(_toast_label)
	_toast_panel.visible = false
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_panel)


func refresh() -> void:
	if Game.state == null:
		return
	_chips_label.text = "● 칩 %d" % Game.state.chips_balance
	_goal_label.text = "목표 · " + Game.current_goal()
	_goal_label.visible = not _goal_collapsed


func toggle_goal() -> void:
	_goal_collapsed = not _goal_collapsed
	_goal_toggle.text = "목표 보기 (Tab)" if _goal_collapsed else "목표 접기 (Tab)"
	refresh()


func set_location_name(text: String) -> void:
	_location_label.text = text


func set_prompt(target: Dictionary) -> void:
	_prompt_button.visible = not target.is_empty()
	if not target.is_empty():
		_prompt_button.text = "[E]  " + str(target["prompt"])


func prompt_text() -> String:
	return _prompt_button.text if _prompt_button.visible else ""


func show_toast(text: String) -> void:
	_toast_label.text = text
	_toast_panel.visible = true
	_toast_panel.modulate.a = 1.0
	_toast_panel.reset_size()
	_toast_panel.offset_left = -_toast_panel.size.x / 2.0
	_toast_panel.offset_right = _toast_panel.size.x / 2.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.4)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(func(): _toast_panel.visible = false)


func toast_text() -> String:
	return _toast_label.text if _toast_panel.visible else ""


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("toggle_goal"):
		toggle_goal()
		get_viewport().set_input_as_handled()
