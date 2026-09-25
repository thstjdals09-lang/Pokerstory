extends Control
## Pause menu: resume, collection book (6 categories, equip), journal (tasks, tracking),
## neighbours (friendship, rivalry, romance, memories), save, back to title, quit (both save first).

signal resume_requested
signal save_requested
signal title_requested
signal quit_requested

const ItemIcon := preload("res://scripts/ui/item_icon.gd")
const CATEGORY_NAMES := {
	"furniture": "가구", "decor": "장식", "clothing": "옷", "card_back": "카드 뒷면",
	"chip_style": "칩 장식", "memento": "기념품",
}

var resume_button: Button
var collection_button: Button
var journal_button: Button
var relations_button: Button
var save_button: Button
var title_button: Button
var quit_button: Button
## Collection: category -> tab button, item_id -> equip button (tests use these).
var category_buttons := {}
var equip_buttons := {}
## Journal: quest_id -> "track" button.
var track_buttons := {}
var category := "furniture"
var _main: VBoxContainer
var _book: VBoxContainer
var _tabs: HBoxContainer
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
	journal_button = UiKit.button("일지 (부탁·이야기)", 360)
	relations_button = UiKit.button("이웃", 360)
	save_button = UiKit.button("저장하기", 360)
	title_button = UiKit.button("저장하고 타이틀로", 360)
	quit_button = UiKit.button("저장하고 게임 종료", 360)
	for b in [resume_button, collection_button, journal_button, relations_button, save_button, title_button, quit_button]:
		_main.add_child(b)
	resume_button.pressed.connect(func(): resume_requested.emit())
	collection_button.pressed.connect(show_collection)
	journal_button.pressed.connect(show_journal)
	relations_button.pressed.connect(show_relations)
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
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	_book.add_child(_tabs)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_book.add_child(scroll)
	_book_list = VBoxContainer.new()
	_book_list.add_theme_constant_override("separation", 8)
	_book_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_book_list)
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


func _open_book(title: String) -> void:
	_main.visible = false
	_book.visible = true
	_book_title.text = title
	UiKit.clear_children(_tabs)
	UiKit.clear_children(_book_list)


# --- collection -------------------------------------------------------------------

## The book keeps "found", "owned", "placed" and "equipped" apart: placing or trading an item never
## removes it from the book.
func show_collection(cat: String = "") -> void:
	if cat != "":
		category = cat
	var found := 0
	for item_id in Game.data.item_order:
		found += 1 if Game.state.collection.has(item_id) else 0
	_open_book("수집 도감  %d / %d" % [found, Game.data.item_order.size()])
	category_buttons.clear()
	equip_buttons.clear()
	for c in DataDB.ITEM_CATEGORIES:
		var n := 0
		var have := 0
		for item_id in Game.data.item_order:
			if str(Game.data.items[item_id].get("category", "")) == c:
				n += 1
				have += 1 if Game.state.collection.has(item_id) else 0
		var b := UiKit.button("%s %d/%d" % [CATEGORY_NAMES[c], have, n], 0)
		b.disabled = c == category
		b.pressed.connect(show_collection.bind(c))
		_tabs.add_child(b)
		category_buttons[c] = b
	for item_id in Game.data.item_order:
		var item: Dictionary = Game.data.items[item_id]
		if str(item.get("category", "")) != category:
			continue
		var known := Game.state.collection.has(item_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var icon := ItemIcon.new()
		icon.setup(item, not known)
		row.add_child(icon)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UiKit.label(str(item["name"]) if known else "???", 19))
		info.add_child(UiKit.wrap_label(str(item.get("description", "")) if known else "아직 발견하지 못했어요.", 14, UiKit.MUTED))
		if known:
			info.add_child(UiKit.label(item_status(item_id), 14, UiKit.MUTED))
		row.add_child(info)
		if DataDB.EQUIP_CATEGORIES.has(category) and Game.state.owned_count(item_id) > 0:
			var on: bool = Game.state.equipped.get(category, "") == item_id
			var eb := UiKit.button("착용 해제" if on else "착용하기", 140)
			eb.pressed.connect(_toggle_equip.bind(item_id, on))
			row.add_child(eb)
			equip_buttons[item_id] = eb
		_book_list.add_child(row)


func item_status(item_id: String) -> String:
	var parts: Array = ["보유 %d" % Game.state.owned_count(item_id)]
	if Game.state.is_item_placed(item_id):
		parts.append("집에 놓음")
	var cat := str(Game.data.items[item_id].get("category", ""))
	if Game.state.equipped.get(cat, "") == item_id:
		parts.append("착용 중")
	return " · ".join(parts)


func _toggle_equip(item_id: String, on: bool) -> void:
	var cat := str(Game.data.items[item_id]["category"])
	if on:
		Game.unequip(cat)
	else:
		Game.equip(item_id)
	show_collection(cat)


func collection_text() -> String:
	var parts: Array = [_book_title.text]
	for row in _book_list.get_children():
		for c in row.get_children():
			if c is VBoxContainer:
				parts.append(c.get_child(0).text)
	return " | ".join(parts)


# --- journal ----------------------------------------------------------------------

func show_journal() -> void:
	_open_book("일지")
	track_buttons.clear()
	var any := false
	for kind in ["quest", "episode"]:
		_book_list.add_child(UiKit.label("주민의 부탁" if kind == "quest" else "주민 이야기", 20, UiKit.ACCENT))
		for id in Game.data.quest_order:
			var q: Dictionary = Game.data.quests[id]
			if q.get("kind", "quest") != kind or QuestBook.state_of(Game.state, id) != QuestBook.ACTIVE:
				continue
			any = true
			var row := HBoxContainer.new()
			var info := VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.add_child(UiKit.label(("▶ " if Game.state.tracked_quest == id else "") + str(q["name"]), 18))
			var where := str(q["objective"]) if q.has("objective") else "%s — %s" % [Game.speaker_name(_speaker(str(q["target"]))), Game.npc_where_text(str(q["target"]))]
			info.add_child(UiKit.wrap_label(where, 14, UiKit.MUTED))
			row.add_child(info)
			var tb := UiKit.button("따라가기", 120)
			tb.disabled = Game.state.tracked_quest == id
			tb.pressed.connect(_track.bind(id))
			row.add_child(tb)
			track_buttons[id] = tb
			_book_list.add_child(row)
	if not any:
		_book_list.add_child(UiKit.wrap_label("진행 중인 부탁이나 이야기가 없어요. 머리 위에 ! 표시가 있는 주민에게 말을 걸어 보세요.", 16, UiKit.MUTED))
	var done := 0
	for id in Game.state.quests:
		done += 1 if Game.state.quests[id] == QuestBook.COMPLETED else 0
	_book_list.add_child(UiKit.label("마친 부탁·이야기 %d개 · 아르바이트 %d회" % [done, Game.state.jobs_completed], 15, UiKit.MUTED))


func _track(quest_id: String) -> void:
	Game.track_quest(quest_id)
	show_journal()


func _speaker(target: String) -> String:
	return target if Game.data.npcs.has(target) else "obj:" + target


# --- neighbours -------------------------------------------------------------------

func show_relations() -> void:
	_open_book("이웃")
	for npc in Game.data.npc_order:
		var def: Dictionary = Game.data.npcs[npc]
		if not Game.state.has_met(npc):
			_book_list.add_child(UiKit.label("??? — 아직 만나지 않았어요", 16, UiKit.MUTED))
			continue
		var r: Dictionary = Game.state.relation(npc)
		var line := "%s (%s) — 친밀 %d · 라이벌 %d · 함께한 판 %d" % [def["name"], def.get("role", ""), int(r["friendship"]), int(r["rivalry"]), int(r["poker_hands"])]
		var stage := str(r["romance"]["stage"])
		if stage in ["dating", "committed"]:
			line += " · " + ("만나는 중" if stage == "dating" else "함께")
		_book_list.add_child(UiKit.label(line, 16))
		if not r["memories"].is_empty():
			var names: Array = []
			for m in r["memories"]:
				names.append(str(Game.data.quests.get(m, {}).get("name", m)))
			_book_list.add_child(UiKit.wrap_label("  기억: " + ", ".join(names), 14, UiKit.MUTED))


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("menu"):
		if _book.visible:
			show_main()
		else:
			resume_requested.emit()
		get_viewport().set_input_as_handled()
