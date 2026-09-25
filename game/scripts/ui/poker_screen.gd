extends Control
## The poker table (spec v0.2 P3-P5, content v0.3 05_poker): 5 cards each, one ability taken to
## the table, replace up to 3 cards once, showdown, then the payout. The mode (practice, home game,
## social mix, friendly challenge, tournament) changes the stake line, the opponent and the words
## around the table, never the rules. Everything can be finished by pressing "그대로 승부" alone.

signal exit_requested

const CardView := preload("res://scripts/ui/card_view.gd")

var match_ref: PokerMatch = null
var last_result := {}
var ability_button: Button
## Swaps the carried ability before it is used (no separate loadout step before each hand).
var switch_button: Button
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
## lucky_mark: the next card click marks that card instead of selecting it.
var _marking := false
## The showdown result could not be saved: nothing is paid yet; "다시 저장하기" retries the same result.
var save_retry := false
var _spectators: Array = []
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

	_opp_hand_label = UiKit.label("", 18, Color("#f3dfc1"))
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
	switch_button = UiKit.button("능력 바꾸기", 130)
	switch_button.pressed.connect(cycle_ability)
	draw_button = UiKit.button("", 170)
	draw_button.pressed.connect(do_draw)
	stand_button = UiKit.button("그대로 승부", 150)
	stand_button.pressed.connect(do_stand)
	help_button = UiKit.button("족보 도움말", 130)
	help_button.pressed.connect(func(): _help_panel.visible = not _help_panel.visible)
	leave_button = UiKit.button("나가기 (Esc)", 130)
	leave_button.pressed.connect(request_leave)
	for b in [ability_button, switch_button, draw_button, stand_button, help_button, leave_button]:
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

func start(m: PokerMatch, spectators: Array = []) -> void:
	match_ref = m
	last_result = {}
	save_retry = false
	_ability = Game.match_ability(m)
	_selected.clear()
	_notice = ""
	_marking = false
	_spectators = spectators
	# A resumed hand shows what the ability already revealed.
	var known: Dictionary = m.ability_results.get(_ability.get("id", ""), {})
	_ability_text = _ability_result_text(known) if not known.is_empty() else ""
	_notice = Game.poker_opening(m)
	_help_panel.visible = false
	_confirm_panel.get_parent().visible = false
	visible = true
	refresh()
	stand_button.grab_focus.call_deferred()


func refresh() -> void:
	var showdown := match_ref.phase == PokerMatch.Phase.SHOWDOWN
	var opp_name := opponent_name()
	var stake := hand_stake()
	var mode_name := str(Game.poker_mode(match_ref.mode).get("name", "포커 모임"))
	if match_ref.mode == "tournament":
		var names: Array = Game.poker_mode("tournament").get("stage_names", [])
		var st := int(Game.state.tournament.get("stage", 0))
		mode_name += " · %s" % (names[st] if st < names.size() else "")
	if stake == 0:
		_header.text = "%s · 5장 원드로 · 칩 없이 연습    보유 칩 %d" % [mode_name, Game.state.chips_balance]
	else:
		_header.text = "%s · 5장 원드로 · 판돈 %d칩 (나 %d + %s %d)    보유 칩 %d" % [mode_name, stake * 2, stake, opp_name, stake, Game.state.chips_balance]
	for i in 5:
		# Opponent cards are handed to the UI only at showdown.
		if showdown:
			opponent_views[i].show_card(match_ref.opponent_hand[i])
		else:
			opponent_views[i].show_back()
		player_views[i].show_card(match_ref.player_hand[i])
		player_views[i].marked = i == match_ref.locked_index
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
	ability_button.text = "%s (%s)" % [_ability.get("name", "능력"), ("카드를 고르세요" if _marking else "1회") if uses_left else "사용함"]
	ability_button.tooltip_text = str(_ability.get("description", ""))
	ability_button.disabled = not uses_left
	switch_button.visible = Game.state.abilities_unlocked.size() > 1
	switch_button.disabled = showdown or not match_ref.ability_results.is_empty() or _marking
	draw_button.text = "교체하기 (%d장)" % _selected.size()
	draw_button.disabled = showdown or _selected.is_empty()
	stand_button.disabled = showdown
	leave_button.disabled = false
	_result_panel.visible = showdown
	if showdown:
		var can_again := Game.can_join_poker(match_ref.mode)
		again_button.disabled = not can_again
		if stake == 0:
			again_button.text = "한 판 더 (연습)"
		else:
			again_button.text = "한 판 더 (참가금 %d)" % stake if can_again else "칩 부족 (%d 필요)" % stake
		result_leave_button.disabled = save_retry
		if save_retry:
			again_button.disabled = false
			again_button.text = "다시 저장하기"


func opponent_name() -> String:
	return Game.data.npc_name(Game.match_opponent(match_ref))


## The stake of this hand (hands saved before content v0.3 carry the economy stake).
func hand_stake() -> int:
	return match_ref.stake if match_ref.stake >= 0 else Game.poker_stake()


func toggle_card(i: int) -> void:
	if match_ref == null or match_ref.phase != PokerMatch.Phase.DRAW:
		return
	_notice = ""
	if _marking:
		_marking = false
		var r: Dictionary = Game.use_poker_ability(match_ref, _ability, {"index": i})
		if r["ok"]:
			_selected.erase(i)
			_ability_text = _ability_result_text(r)
		refresh()
		return
	if i == match_ref.locked_index:
		_notice = "표시한 카드는 바꾸지 않도록 잠겨 있어요."
	elif _selected.has(i):
		_selected.erase(i)
	elif _selected.size() < match_ref.max_discards:
		_selected.append(i)
	else:
		_notice = "최대 %d장까지 바꿀 수 있어요." % match_ref.max_discards
	refresh()


func cycle_ability() -> void:
	var list: Array = Game.state.abilities_unlocked
	var i := list.find(match_ref.ability_id)
	select_ability(str(list[(i + 1) % list.size()]))


func select_ability(ability_id: String) -> void:
	if Game.switch_ability(match_ref, ability_id):
		_ability = Game.match_ability(match_ref)
		_notice = "가져간 능력: %s — %s" % [_ability.get("name", ""), _ability.get("description", "")]
	refresh()


func use_ability() -> void:
	if not match_ref.can_use_ability(_ability):
		return
	match str(_ability.get("effect", "")):
		"lock_card":
			_marking = true
			_notice = "표시할 카드를 한 장 고르세요. 그 카드는 실수로 바꾸지 않게 잠겨요."
			refresh()
			return
		"undo_selection":
			if _selected.is_empty():
				_notice = "되돌릴 선택이 없어요. 바꿀 카드를 고른 뒤에 쓸 수 있어요."
				refresh()
				return
	var r: Dictionary = Game.use_poker_ability(match_ref, _ability)
	if r["ok"]:
		_ability_text = _ability_result_text(r)
		if r.get("undo", false):
			_selected.clear()
		if str(r.get("effect", "")) == "help_focus":
			_help_panel.visible = true
	refresh()


func _ability_result_text(r: Dictionary) -> String:
	var name := str(_ability.get("name", "능력"))
	match str(r.get("effect", _ability.get("effect", ""))):
		"reveal_opponent_pair_or_better":
			return str(_ability["result_true"] if r.get("pair_or_better", false) else _ability["result_false"])
		"own_suit_count":
			return "%s: 내 패에서 %s 문양이 %d장으로 가장 많아요." % [name, r.get("suit", "?"), int(r.get("count", 0))]
		"discard_hint":
			var keep: Array = r.get("keep", [])
			if keep.is_empty():
				return "%s: 지금은 %s. 높은 카드를 남기고 낮은 카드를 바꾸는 방법이 있어요. (결과를 보장하지 않아요)" % [name, r.get("hand", "")]
			return "%s: 지금 %s — %s번째 카드가 족보를 만들고 있어요. 나머지를 바꾸면 족보는 유지돼요. (결과를 보장하지 않아요)" % [name, r.get("hand", ""), ", ".join(keep.map(func(i): return str(int(i) + 1)))]
		"undo_selection":
			return "%s: 고른 카드를 모두 되돌렸어요." % name
		"opponent_last_discards":
			if not r.get("known", false):
				return "%s: 이 상대와 친 기록이 아직 없어요." % name
			return "%s: 지난 판에 %s은(는) %d장을 바꿨어요." % [name, opponent_name(), int(r.get("discards", 0))]
		"lock_card":
			return "%s: %d번째 카드에 표시를 남겼어요. 이 카드는 바뀌지 않아요." % [name, int(r.get("index", 0)) + 1]
		"opponent_pattern":
			if not r.get("known", false):
				return "%s: 이 상대의 공개된 판 기록이 아직 없어요." % name
			return "%s: 공개된 %d판 기록 — 평균 %.1f장 교체, 자주 보인 족보는 %s." % [name, int(r.get("hands_seen", 0)), float(r.get("avg_discards", 0.0)), r.get("common_hand", "")]
		"help_focus":
			return "%s: 지금 내 패는 %s이에요. 도움말을 펼쳐 두었어요. 서두를 필요 없어요." % [name, r.get("hand", "")]
	return ""


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
	save_retry = last_result.get("reason", "") == "save_failed"
	if save_retry:
		_result_title.text = "저장하지 못했어요"
		_result_detail.text = "이번 판 결과를 저장하지 못해 아직 정산하지 않았어요.\n칩은 그대로예요. 같은 결과로 다시 저장해 주세요."
		_result_line.text = ""
		refresh()
		again_button.grab_focus.call_deferred()
		return
	var key: String = last_result.get("outcome", PokerEconomy.outcome_key(match_ref.outcome))
	_result_title.text = {"win": "승리!", "draw": "무승부", "lose": "아쉽게 졌어요"}[key] + (" (연습)" if last_result.get("practice", false) else "")
	var paid_in := int(last_result.get("stake", 0))
	var payout := int(last_result.get("payout", 0))
	var lines: Array = []
	if last_result.get("practice", false):
		key = "practice_" + key
	match key:
		"practice_win", "practice_draw", "practice_lose":
			lines.append("연습 판이라 칩은 그대로예요.")
		"win":
			lines.append("판돈 %d칩 획득  (순이익 +%d)" % [payout, payout - paid_in])
		"draw":
			lines.append("참가금 %d칩 돌려받음  (손익 0)" % payout)
		_:
			lines.append("참가금 %d칩을 잃었어요  (순손실 -%d)" % [paid_in, paid_in - payout])
	if last_result.has("tournament_stage"):
		if last_result.get("tournament_won", false):
			lines.append("네잎 저녁제 대회 우승!" + (" 기념 카드 뒷면을 받았어요." if last_result.has("reward_item") else " (우승 기념품은 이미 받았어요)"))
		else:
			var names: Array = Game.poker_mode("tournament").get("stage_names", [])
			var st := int(last_result["tournament_stage"])
			lines.append("대회 다음 단계: %s (%s)" % [names[st] if st < names.size() else "", Game.data.npc_name(Game.tournament_opponent())])
	lines.append_array(Game.poker_result_notes(match_ref, last_result))
	lines.append("보유 칩  %d" % Game.state.chips_balance)
	_result_detail.text = "\n".join(lines)
	var outcome := PokerEconomy.outcome_key(match_ref.outcome)
	var said: Array = ["%s: \"%s\"" % [opponent_name(), Game.opponent_line(Game.match_opponent(match_ref), outcome)]]
	var cheers: Array = Game.data.poker.get("spectator_lines", {}).get(outcome, [])
	for i in _spectators.size():
		if not cheers.is_empty():
			said.append("%s: \"%s\"" % [Game.data.npc_name(_spectators[i]), cheers[i % cheers.size()]])
	_result_line.text = "\n".join(said)
	refresh()
	again_button.grab_focus.call_deferred()


func _on_again() -> void:
	if save_retry:
		_finish()
		return
	var mode := match_ref.mode
	var opponent := "" if mode == "tournament" else match_ref.opponent_id
	var m := Game.create_poker_match(mode, opponent, match_ref.ability_id)
	if m != null:
		start(m, _spectators)


func _hide_confirm() -> void:
	_confirm_panel.get_parent().visible = false


func _confirm_leave() -> void:
	_hide_confirm()
	var r: Dictionary = Game.fold_match(match_ref)
	if r.get("reason", "") == "save_failed":
		show_notice("저장하지 못해서 자리에 그대로 있어요. 판은 계속 이어져요.")
		return
	exit_requested.emit()


func request_leave() -> void:
	if match_ref != null and match_ref.phase == PokerMatch.Phase.DRAW:
		if hand_stake() == 0:
			_confirm_label.text = "연습 판을 여기서 끝낼까요? 칩은 그대로예요."
		else:
			_confirm_label.text = "지금 일어나면 이번 판은 포기로 처리되어 참가금 %d칩을 돌려받지 못해요. 일어날까요?" % hand_stake()
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
