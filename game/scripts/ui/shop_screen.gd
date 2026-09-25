extends Control
## Shop window (spec P6). Anyone can browse; the buy button states the chips needed when short.

signal closed

const ItemIcon := preload("res://scripts/ui/item_icon.gd")

## item_id -> Button, exposed for tests.
var buy_buttons := {}
var close_button: Button
var shop_id := ""
var _title: Label
var _chips: Label
var _list: VBoxContainer
var _message: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UiKit.dim_background())
	var panel := UiKit.panel(UiKit.PAPER, 20)
	panel.custom_minimum_size = Vector2(640, 0)
	add_child(UiKit.centered(panel))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_title = UiKit.label("", 26, UiKit.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_chips = UiKit.label("", 20)
	head.add_child(_chips)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	col.add_child(_list)
	_message = UiKit.wrap_label("", 17, UiKit.MUTED)
	col.add_child(_message)
	close_button = UiKit.button("닫기 (Esc)", 150)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_button.pressed.connect(close)
	col.add_child(close_button)
	visible = false


func open(p_shop_id: String) -> void:
	shop_id = p_shop_id
	_message.text = "무엇이든 구경해 보세요."
	visible = true
	refresh()


func refresh() -> void:
	var shop: Dictionary = Game.data.shops.get(shop_id, {})
	_title.text = str(shop.get("name", "상점"))
	_chips.text = "● 보유 칩 %d" % Game.state.chips_balance
	UiKit.clear_children(_list)
	buy_buttons.clear()
	for item_id in Game.shop_items(shop_id):
		var item: Dictionary = Game.data.items[item_id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var icon := ItemIcon.new()
		icon.setup(item)
		row.add_child(icon)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UiKit.label("%s  ·  %d 칩" % [item["name"], int(item["price"])], 20))
		info.add_child(UiKit.wrap_label(str(item.get("description", "")), 15, UiKit.MUTED))
		var placed := 1 if Game.state.is_item_placed(item_id) else 0
		info.add_child(UiKit.label("보관함 %d개 · 집에 놓음 %d개" % [Game.state.owned_count(item_id), placed], 14, UiKit.MUTED))
		row.add_child(info)
		var price := int(item["price"])
		var short := price - Game.state.chips_balance
		var buy := UiKit.button("사기" if short <= 0 else "칩 부족 (%d 더 필요)" % short, 190)
		buy.disabled = short > 0
		buy.pressed.connect(buy_item.bind(item_id))
		row.add_child(buy)
		_list.add_child(row)
		buy_buttons[item_id] = buy
	if not buy_buttons.is_empty():
		var first: Button = buy_buttons.values()[0]
		(close_button if first.disabled else first).grab_focus.call_deferred()


func buy_item(item_id: String) -> void:
	var r := Game.buy_item(item_id)
	var item_name := str(Game.data.items[item_id]["name"])
	if r["ok"]:
		_message.text = "%s을(를) 샀어요! 집 보관함에서 꾸미기로 놓을 수 있어요." % item_name
	elif r["reason"] == "save_failed":
		_message.text = "저장하지 못해서 구매를 취소했어요. 칩과 물건은 그대로예요. 다시 시도해 주세요."
	elif r["reason"] == "not_enough_chips":
		_message.text = "칩이 %d개 부족해요. 카드룸 포커는 참가비 없이 언제든 할 수 있어요." % int(r["need"])
	refresh()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("menu"):
		close()
		get_viewport().set_input_as_handled()
