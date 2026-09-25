extends Control
## The evening poker table (spec v0.2 P3-P5): 5 cards each, optional Star Sense,
## replace up to 3 cards once, showdown, then the payout. Everything can be finished
## by pressing "그대로 승부" alone.

signal exit_requested

const CardView := preload("res://scripts/ui/card_view.gd")

var match_ref: PokerMatch = null
var last_result := {}
var ability_button: Button
var draw_button: Button
var stand_button: Button
var help_button: Button
var leave_button: Button
var again_button: Button
var result_leave_button: Button
var confirm_leave_button: Button
var opponent_views: Array = []
var player_views: Array = []

var _header: Label
var _ability := {}
var _selected: Array = []
var _ability_text := ""
var _notice := ""
var _opp_hand_label: Label
var _player_hand_label: Label
var _message_label: Label
var _ability_label: Label
var _result_panel: PanelContainer
var _result_title: Label
var _result_detail: Label
var _result_line: Label
var _help_panel: PanelContainer
var _confirm_panel: PanelContainer
var _confirm_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.09, 0.08, 0.93)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_top = 16
	col.offset_bottom = -16
	col.add_theme_constant_override("separation", 8)
	add_child(col)

	_header = UiKit.label("", 22, Color("#f3dfc1"))
	var header := _header
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(header)

	var opp_name := Game.data.npc_name(str(Game.poker_rules().get("opponent", "")))
	_opp_hand_label = UiKit.label(opp_name, 18, Color("#f3dfc1"))
	_opp_hand_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_opp_hand_label)
	col.add_child(_card_row(opponent_views, false))

	var middle := VBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.alignment = BoxContainer.ALIGNMENT_CENTER
	middle.add_theme_constant_override("separation", 6)
	col.add_child(middle)
	_message_label = UiKit.wrap_label("", 19, Color("#fff3d6"))
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(_message_label)
	_ability_label = UiKit.wrap_label("", 18, Color("#ffd27a"))
	_ability_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(_ability_label)

	# Result: compact two-column panel so both hands stay fully visible.
	_result_panel = UiKit.panel(UiKit.PAPER, 12)
	_result_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var rb := VBoxContainer.new()
	rb.add_theme_constant_override("separation", 6)
	_result_panel.add_child(rb)
	var rtop := HBoxContainer.new()
	rtop.add_theme_constant_override("separation", 28)
	rb.add_child(rtop)
	var rleft := VBoxContainer.new()
	rleft.add_theme_constant_override("separation", 2)
	rtop.add_child(rleft)
	_result_title = UiKit.label("", 26, UiKit.ACCENT)
	rleft.add_child(_result_title)
	_result_detail = UiKit.label("", 17)
	rleft.add_child(_result_detail)
	var rbuttons := VBoxContainer.new()
	rbuttons.alignment = BoxContainer.ALIGNMENT_CENTER
	rbuttons.add_theme_constant_override("separation", 8)
	rtop.add_child(rbuttons)
	again_button = UiKit.button("한 판 더", 200)
	again_button.pressed.connect(_on_again)
	result_leave_button = UiKit.button("자리에서 일어나기", 200)
	result_leave_button.pressed.connect(func(): exit_requested.emit())
	rbuttons.add_child(again_button)
	rbuttons.add_child(result_leave_button)
	_result_line = UiKit.label("", 16, UiKit.MUTED)
	rb.add_child(_result_line)
	middle.add_child(_result_panel)

	_player_hand_label = UiKit.label("", 18, Color("#fff3d6"))
	_player_hand_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_player_hand_label)
	col.add_child(_card_row(player_views, true))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	col.add_child(buttons)
	ability_button = UiKit.button("", 190)
	ability_button.pressed.connect(use_ability)
	draw_button = UiKit.button("", 170)
	draw_button.pressed.connect(do_draw)
	stand_button = UiKit.button("그대로 승부", 150)
	stand_button.pressed.connect(do_stand)
	help_button = UiKit.button("족보 도움말", 130)
	help_button.pressed.connect(func(): _help_panel.visible = not _help_panel.visible)
	leave_button = UiKit.button("나가기 (Esc)", 130)
	leave_button.pressed.connect(request_leave)
	for b in [ability_button, draw_button, stand_button, help_button, leave_button]:
		buttons.add_child(b)

	_build_help_panel()
	_build_confirm_panel()
	visible = false


func _card_row(views: Array, interactive: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	for i in 5:
		var v := CardView.new()
		v.index = i
		v.interactive = interactive
		v.lift_space = interactive
		if interactive:
			v.pressed.connect(toggle_card)
		row.add_child(v)
		views.append(v)
	return row


func _build_help_panel() -> void:
	_help_panel = UiKit.panel(UiKit.PAPER, 14)
	_help_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_help_panel.offset_left = -470
	_help_panel.offset_right = -16
	_help_panel.offset_top = -230
	_help_panel.offset_bottom = 230
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_help_panel.add_child(box)
	box.add_child(UiKit.label("족보 (위가 높음)", 19, UiKit.ACCENT))
	for row in Game.data.poker.get("hand_help", []):
		box.add_child(UiKit.label("%s — %s" % [row[0], row[1]], 15))
	box.add_child(UiKit.wrap_label("같은 족보면 높은 숫자가 이겨요. 무늬로는 가리지 않아요. 완전히 같으면 무승부.", 15, UiKit.MUTED))
	var close := UiKit.button("닫기", 110)
	close.pressed.connect(func(): _help_panel.visible = false)
	box.add_child(close)
	_help_panel.visible = false
	add_child(_help_panel)


func _build_confirm_panel() -> void:
	_confirm_panel = UiKit.panel(UiKit.PAPER, 18)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_confirm_panel.add_child(box)
	_confirm_label = UiKit.label("", 18)
	box.add_child(_confirm_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	confirm_leave_button = UiKit.button("나가기", 140)
	confirm_leave_button.pressed.connect(_confirm_leave)
	var stay := UiKit.button("계속하기", 140)
	stay.pressed.connect(_hide_confirm)
	row.add_child(confirm_leave_button)
	row.add_child(stay)
	var holder := UiKit.centered(_confirm_panel)
	holder.visible = false
	add_child(holder)


# --- flow ----------------------------------------------------------------------

func start(m: PokerMatch) -> void:
	match_ref = m
	last_result = {}
	_ability = Game.player_ability()
	_selected.clear()
	_notice = ""
	# A resumed hand shows what the ability already revealed.
	var known: Dictionary = m.ability_results.get(_ability.get("id", ""), {})
	_ability_text = _ability_result_text(known) if not known.is_empty() else ""
	_help_panel.visible = false
	_confirm_panel.get_parent().visible = false
	visible = true
	refresh()
	stand_button.grab_focus.call_deferred()


func refresh() -> void:
	var showdown := match_ref.phase == PokerMatch.Phase.SHOWDOWN
	var opp_name := Game.data.npc_name(str(Game.poker_rules().get("opponent", "")))
	var stake := Game.poker_stake()
	_header.text = "저녁 포커 모임 · 5장 원드로 · 판돈 %d칩 (나 %d + %s %d)    보유 칩 %d" % [stake * 2, stake, opp_name, stake, Game.state.chips_balance]
	for i in 5:
		# Opponent cards are handed to the UI only at showdown.
		if showdown:
			opponent_views[i].show_card(match_ref.opponent_hand[i])
		else:
			opponent_views[i].show_back()
		player_views[i].show_card(match_ref.player_hand[i])
		player_views[i].set_selected(_selected.has(i))
		player_views[i].interactive = not showdown
	var max_d := match_ref.max_discards
	if showdown:
		_opp_hand_label.text = "%s의 패: %s   (%d장 교체)" % [opp_name, match_ref.opponent_eval["name"], match_ref.opponent_discards.size()]
		_player_hand_label.text = "내 패: " + str(match_ref.player_eval["name"])
		_message_label.text = ""
	else:
		_opp_hand_label.text = "%s (카드는 승부 때 공개돼요)" % opp_name
		_player_hand_label.text = "내 패: " + str(match_ref.current_player_eval()["name"])
		_message_label.text = _notice if _notice != "" else "바꿀 카드를 최대 %d장 고르세요 (클릭 또는 숫자키 1~5). 바꾸지 않고 승부해도 돼요." % max_d
	_ability_label.text = _ability_text
	_message_label.visible = not showdown
	_ability_label.visible = not showdown and _ability_text != ""
	var uses_left := match_ref.can_use_ability(_ability)
	ability_button.text = "%s (%s)" % [_ability.get("name", "능력"), "1회" if uses_left else "사용함"]
	ability_button.tooltip_text = str(_ability.get("description", ""))
	ability_button.disabled = not uses_left
	draw_button.text = "교체하기 (%d장)" % _selected.size()
	draw_button.disabled = showdown or _selected.is_empty()
	stand_button.disabled = showdown
	leave_button.disabled = false
	_result_panel.visible = showdown
	if showdown:
		var can_again := Game.can_join_poker()
		again_button.disabled = not can_again
		again_button.text = "한 판 더 (참가금 %d)" % stake if can_again else "칩 부족 (%d 필요)" % stake


func toggle_card(i: int) -> void:
	if match_ref == null or match_ref.phase != PokerMatch.Phase.DRAW:
		return
	_notice = ""
	if _selected.has(i):
		_selected.erase(i)
	elif _selected.size() < match_ref.max_discards:
		_selected.append(i)
	else:
		_notice = "최대 %d장까지 바꿀 수 있어요." % match_ref.max_discards
	refresh()


func use_ability() -> void:
	var r: Dictionary = Game.use_poker_ability(match_ref, _ability)
	if r["ok"]:
		_ability_text = _ability_result_text(r)
	refresh()


func _ability_result_text(r: Dictionary) -> String:
	return str(_ability["result_true"] if r.get("pair_or_better", false) else _ability["result_false"])


## A one-off message in the message line (cleared by the next card selection).
func show_notice(text: String) -> void:
	_notice = text
	refresh()


func do_draw() -> void:
	if _selected.is_empty():
		return
	var indices := _selected.duplicate()
	indices.sort()
	if match_ref.player_draw(indices):
		_finish()


func do_stand() -> void:
	if match_ref.player_draw([]):
		_finish()


func _finish() -> void:
	_selected.clear()
	last_result = Game.settle_match(match_ref)
	var key: String = last_result.get("outcome", PokerEconomy.outcome_key(match_ref.outcome))
	_result_title.text = {"win": "승리!", "draw": "무승부", "lose": "아쉽게 졌어요"}[key]
	var paid_in := int(last_result.get("stake", 0))
	var payout := int(last_result.get("payout", 0))
	var lines: Array = []
	match key:
		"win":
			lines.append("판돈 %d칩 획득  (순이익 +%d)" % [payout, payout - paid_in])
		"draw":
			lines.append("참가금 %d칩 돌려받음  (손익 0)" % payout)
		_:
			lines.append("참가금 %d칩을 잃었어요  (순손실 -%d)" % [paid_in, paid_in - payout])
	lines.append("보유 칩  %d" % Game.state.chips_balance)
	_result_detail.text = "\n".join(lines)
	var opp_name := Game.data.npc_name(str(Game.poker_rules().get("opponent", "")))
	_result_line.text = "%s: \"%s\"" % [opp_name, Game.data.poker.get("opponent_lines", {}).get(key, "")]
	refresh()
	again_button.grab_focus.call_deferred()


func _on_again() -> void:
	var m := Game.create_poker_match()
	if m != null:
		start(m)


func _hide_confirm() -> void:
	_confirm_panel.get_parent().visible = false


func _confirm_leave() -> void:
	_hide_confirm()
	Game.fold_match(match_ref)
	exit_requested.emit()


func request_leave() -> void:
	if match_ref != null and match_ref.phase == PokerMatch.Phase.DRAW:
		_confirm_label.text = "지금 일어나면 이번 판은 포기로 처리되어 참가금 %d칩을 돌려받지 못해요. 일어날까요?" % Game.poker_stake()
		_confirm_panel.get_parent().visible = true
		confirm_leave_button.grab_focus.call_deferred()
	else:
		exit_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu"):
		request_leave()
		get_viewport().set_input_as_handled()
		return
	for i in 5:
		if event.is_action_pressed("card_%d" % (i + 1)):
			toggle_card(i)
			get_viewport().set_input_as_handled()
			return
