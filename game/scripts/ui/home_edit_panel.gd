extends Control
## Home decorating mode (spec P6, section 3): pick an item from storage, pick one of the
## predefined slots (button or mouse click in the room), then confirm or cancel.
## An occupied slot can be returned to storage. No free grid, rotation or wall editing in v0.2.

signal closed

var world: Node2D = null
var selected_item := ""
var selected_slot := ""
## Exposed for tests.
var item_buttons := {}
var slot_buttons := {}
var confirm_button: Button
var store_button: Button
var close_button: Button
var _items_box: VBoxContainer
var _slots_box: VBoxContainer
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := UiKit.panel(Color(1, 0.97, 0.91, 0.97), 16)
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -330
	panel.offset_right = -14
	panel.offset_top = 80
	panel.offset_bottom = -20
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(UiKit.label("집 꾸미기", 24, UiKit.ACCENT))
	col.add_child(UiKit.label("1. 보관함에서 가구 고르기", 16, UiKit.MUTED))
	_items_box = VBoxContainer.new()
	col.add_child(_items_box)
	col.add_child(UiKit.label("2. 놓을 자리 고르기 (방에서 클릭해도 돼요)", 16, UiKit.MUTED))
	_slots_box = VBoxContainer.new()
	col.add_child(_slots_box)
	_status = UiKit.wrap_label("", 16)
	_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_status)
	confirm_button = UiKit.button("여기에 놓기 (확정)", 280)
	confirm_button.pressed.connect(confirm)
	col.add_child(confirm_button)
	store_button = UiKit.button("보관함으로 되돌리기", 280)
	store_button.pressed.connect(store_selected)
	col.add_child(store_button)
	close_button = UiKit.button("꾸미기 끝내기 (Esc)", 280)
	close_button.pressed.connect(close)
	col.add_child(close_button)
	visible = false


func open(p_world: Node2D) -> void:
	world = p_world
	selected_item = ""
	selected_slot = ""
	visible = true
	_status.text = "가구를 고른 뒤 자리를 고르세요."
	refresh()


func refresh() -> void:
	UiKit.clear_children(_items_box)
	item_buttons.clear()
	for item_id in Game.state.owned_items:
		var item: Dictionary = Game.data.items.get(item_id, {})
		if not item.get("placeable", false):
			continue
		var b := UiKit.button("%s × %d" % [item["name"], Game.state.owned_count(item_id)], 280)
		b.toggle_mode = true
		b.button_pressed = item_id == selected_item
		if item_id == selected_item:
			b.text = "✔ " + b.text
		b.pressed.connect(select_item.bind(item_id))
		_items_box.add_child(b)
		item_buttons[item_id] = b
	if item_buttons.is_empty():
		_items_box.add_child(UiKit.wrap_label("보관함이 비어 있어요. 세라의 잡화점에서 가구를 살 수 있어요.", 15, UiKit.MUTED))

	UiKit.clear_children(_slots_box)
	slot_buttons.clear()
	for s in Game.home_slots():
		var placed := Game.state.placement_at(s["id"])
		var status := "비어 있음" if placed == "" else str(Game.data.items[placed]["name"])
		var b := UiKit.button("%s — %s" % [s["name"], status], 280)
		if s["id"] == selected_slot:
			b.text = "▶ " + b.text
		b.pressed.connect(select_slot.bind(s["id"]))
		_slots_box.add_child(b)
		slot_buttons[s["id"]] = b

	var slot_empty := selected_slot != "" and Game.state.placement_at(selected_slot) == ""
	confirm_button.disabled = not (selected_item != "" and slot_empty)
	store_button.disabled = not (selected_slot != "" and not slot_empty)
	world.set_edit_state(true, selected_slot, selected_item)


func select_item(item_id: String) -> void:
	selected_item = "" if selected_item == item_id else item_id
	_update_status()
	refresh()


func select_slot(slot_id: String) -> void:
	selected_slot = slot_id
	_update_status()
	refresh()


func confirm() -> void:
	if Game.place_item(selected_slot, selected_item):
		_status.text = "%s에 %s을(를) 놓았어요." % [Game.slot_name(selected_slot), Game.data.items[selected_item]["name"]]
		selected_item = ""
		selected_slot = ""
	refresh()


func store_selected() -> void:
	var item_id := Game.state.placement_at(selected_slot)
	if item_id != "" and Game.remove_placement(selected_slot):
		_status.text = "%s을(를) 보관함으로 되돌렸어요." % Game.data.items[item_id]["name"]
		selected_slot = ""
	refresh()


func close() -> void:
	visible = false
	if world:
		world.set_edit_state(false)
	closed.emit()


func _update_status() -> void:
	if selected_slot == "":
		_status.text = "자리를 고르세요." if selected_item != "" else "가구를 고른 뒤 자리를 고르세요."
		return
	var placed := Game.state.placement_at(selected_slot)
	if placed != "":
		_status.text = "%s에는 이미 %s이(가) 있어요. 되돌리면 다시 놓을 수 있어요." % [Game.slot_name(selected_slot), Game.data.items[placed]["name"]]
	elif selected_item == "":
		_status.text = "%s을(를) 골랐어요. 놓을 가구를 고르세요." % Game.slot_name(selected_slot)
	else:
		_status.text = "%s에 놓을까요? '여기에 놓기'를 누르세요." % Game.slot_name(selected_slot)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var slot: String = world.slot_at_mouse()
		if slot != "":
			select_slot(slot)
			get_viewport().set_input_as_handled()
