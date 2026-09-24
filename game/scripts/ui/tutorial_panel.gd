extends Control
## First-time controls tutorial: explains only moving and talking (spec P0). Skippable, never blocks.

signal finished

var step := 0
var _panel: PanelContainer
var _text: Label
var _moved := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = UiKit.panel(Color(0.23, 0.16, 0.12, 0.92), 14)
	# Sits above the interaction prompt so it never covers the player or residents.
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_top = -176
	_panel.offset_bottom = -96
	_panel.offset_left = -330
	_panel.offset_right = 330
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_panel.add_child(row)
	_text = UiKit.wrap_label("", 18, Color("#fff3d6"))
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_text)
	var skip := UiKit.button("건너뛰기", 110, false)
	skip.pressed.connect(skip_tutorial)
	row.add_child(skip)
	visible = false


func start() -> void:
	step = 1
	_moved = 0.0
	_text.text = "① 이동: WASD 또는 방향키로 걸어 보세요."
	visible = true


func notify_moved(distance: float) -> void:
	if step != 1:
		return
	_moved += distance
	if _moved >= 60.0:
		step = 2
		_text.text = "② 대화·입장: 주민이나 문 가까이에서 E 또는 Enter (화면 아래 버튼을 눌러도 돼요)."


func notify_interacted() -> void:
	if step >= 1:
		_finish()


func skip_tutorial() -> void:
	_finish()


func _finish() -> void:
	if step == 0:
		return
	step = 0
	visible = false
	finished.emit()
