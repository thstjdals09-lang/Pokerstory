extends Node
## Root of the game. Owns the current World, the HUD and the overlay screens,
## and routes player intents (talk, enter, poker, shop, decorate, menu) between them.
## ui_mode decides who receives input: only "world" lets the player move.

const WorldScript := preload("res://scripts/world/world.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const TutorialScript := preload("res://scripts/ui/tutorial_panel.gd")
const TitleScript := preload("res://scripts/ui/title_screen.gd")
const DialogueScript := preload("res://scripts/ui/dialogue_box.gd")
const PokerScript := preload("res://scripts/ui/poker_screen.gd")
const ShopScript := preload("res://scripts/ui/shop_screen.gd")
const HomeEditScript := preload("res://scripts/ui/home_edit_panel.gd")
const MenuScript := preload("res://scripts/ui/menu_screen.gd")

var ui_mode := "title"
var world: Node2D = null
var hud: Control
var tutorial: Control
var title: Control
var dialogue: Control
var poker: Control
var shop: Control
var home_edit: Control
var menu: Control
## Last dialogue entry shown, for tests and debugging.
var last_entry_id := ""
var _world_root: Node2D
var _fade: ColorRect
var _caption: Label
var _caption_tween: Tween = null
var _dialogue_npc := ""


func _ready() -> void:
	_world_root = Node2D.new()
	add_child(_world_root)

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	hud = HudScript.new()
	hud_layer.add_child(hud)
	tutorial = TutorialScript.new()
	hud_layer.add_child(tutorial)

	var overlay := CanvasLayer.new()
	overlay.layer = 20
	add_child(overlay)
	dialogue = DialogueScript.new()
	poker = PokerScript.new()
	shop = ShopScript.new()
	home_edit = HomeEditScript.new()
	menu = MenuScript.new()
	for screen in [dialogue, poker, shop, home_edit, menu]:
		overlay.add_child(screen)

	var top := CanvasLayer.new()
	top.layer = 30
	add_child(top)
	title = TitleScript.new()
	top.add_child(title)

	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 50
	add_child(fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.08, 0.05, 0.04, 0.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade)
	_caption = UiKit.label("", 30, Color("#fff3d6"))
	_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_constant_override("outline_size", 8)
	_caption.add_theme_color_override("font_outline_color", Color("#3b2a20"))
	_caption.modulate.a = 0.0
	fade_layer.add_child(_caption)

	title.new_game_requested.connect(start_new_game)
	title.continue_requested.connect(continue_game)
	title.quit_requested.connect(quit_game)
	hud.interact_pressed.connect(_on_hud_interact)
	hud.menu_pressed.connect(open_menu)
	tutorial.finished.connect(_on_tutorial_finished)
	dialogue.choice_picked.connect(_on_dialogue_choice_picked)
	dialogue.closed.connect(_back_to_world)
	poker.exit_requested.connect(_on_poker_exit)
	shop.closed.connect(_back_to_world)
	home_edit.closed.connect(_back_to_world)
	menu.resume_requested.connect(_back_to_world)
	menu.save_requested.connect(func(): menu.set_status("저장했어요." if Game.save_game() else "저장에 실패했어요."))
	menu.title_requested.connect(return_to_title)
	menu.quit_requested.connect(quit_game)
	Game.state_changed.connect(_on_state_changed)
	Game.toast_requested.connect(func(t): hud.show_toast(t))

	show_title()
	if not Game.data_errors.is_empty():
		title.show_message("데이터 오류가 있어요: " + str(Game.data_errors[0]))
	_maybe_start_e2e()


func set_mode(mode: String) -> void:
	ui_mode = mode
	if world:
		world.input_enabled = mode == "world"
	hud.set_prompt(world.focused if world and mode == "world" else {})
	if mode != "world" and mode != "transition":
		_hide_caption()


# --- title and session ---------------------------------------------------------

func show_title() -> void:
	_clear_world()
	Game.end_session()
	hud.visible = false
	tutorial.visible = false
	for screen in [dialogue, poker, shop, home_edit, menu]:
		screen.visible = false
	title.open(Game.has_save())
	set_mode("title")


func start_new_game(player_name: String) -> void:
	Game.new_game(player_name)
	title.visible = false
	hud.visible = true
	await enter_location("village_square", "default")
	if not Game.state.get_flag("tutorial_done"):
		tutorial.start()


func continue_game() -> void:
	var result: Dictionary = Game.load_game()
	if not result["ok"]:
		title.show_message(result["message"])
		return
	title.visible = false
	hud.visible = true
	var s: GameState = Game.state
	var pos = s.player_position if s.has_player_position else null
	var loc_id := s.current_scene if Game.data.locations.has(s.current_scene) else "village_square"
	await enter_location(loc_id, "default", pos)
	var unfinished: PokerMatch = Game.take_resumed_match()
	if unfinished != null:
		set_mode("poker")
		hud.visible = false
		poker.start(unfinished)
		poker.show_notice("중단된 판을 이어서 해요. 참가금은 이미 걸려 있어요.")


func return_to_title() -> void:
	Game.save_game()
	show_title()


func quit_game() -> void:
	if Game.state != null:
		Game.save_game()
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and Game.state != null:
		# An unfinished hand is already saved with its cards; it resumes on the next start.
		Game.save_game()


# --- locations -----------------------------------------------------------------

func enter_location(loc_id: String, spawn_key: String, spawn_position = null, caption: String = "") -> void:
	set_mode("transition")
	if Game.job != null:
		var jd: Dictionary = Game.data.jobs[Game.job.job_id]
		if jd.get("cancel_on_leave", true) and jd.get("location", "") != loc_id:
			Game.cancel_job()
			hud.show_toast("%s을(를) 떠나서 아르바이트를 그만뒀어요. (보수 없음)" % Game.location_name(str(jd.get("location", ""))))
	if world:
		await _fade_to(1.0)
	_clear_world()
	world = WorldScript.new()
	_world_root.add_child(world)
	world.build(loc_id, spawn_key, spawn_position)
	world.interacted.connect(_on_world_interacted)
	world.focus_changed.connect(_on_focus_changed)
	world.player_moved.connect(func(d): tutorial.notify_moved(d))
	Game.set_location(loc_id)
	var loc: Dictionary = Game.data.locations[loc_id]
	hud.set_location_name(("저녁 · " if world.is_evening() else "낮 · ") + str(loc["name"]))
	hud.refresh()
	await _fade_to(0.0)
	if caption != "":
		_show_caption(caption)
	elif loc.has("caption"):
		_show_caption(loc["caption"])
	set_mode("world")


func _clear_world() -> void:
	if world:
		_world_root.remove_child(world)
		world.queue_free()
		world = null


func _fade_to(alpha: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, 0.22)
	await tw.finished


func _show_caption(text: String) -> void:
	_hide_caption()
	_caption.text = text
	_caption_tween = create_tween()
	_caption_tween.tween_property(_caption, "modulate:a", 1.0, 0.25)
	_caption_tween.tween_interval(1.4)
	_caption_tween.tween_property(_caption, "modulate:a", 0.0, 0.5)


## Location captions never cover dialogue, poker or other screens.
func _hide_caption() -> void:
	if _caption_tween:
		_caption_tween.kill()
		_caption_tween = null
	_caption.modulate.a = 0.0


func _on_world_interacted(target: Dictionary) -> void:
	if ui_mode != "world":
		return
	tutorial.notify_interacted()
	match str(target["kind"]):
		"npc":
			open_npc_dialogue(target["id"])
		"door":
			if not Conditions.check(target.get("unlock", {}), Game.state, world.location_id):
				_show_system_dialogue(str(target.get("prompt", "문")), [target.get("locked_text", "아직 들어갈 수 없어요.")], [])
				return
			var needed: String = target.get("requires_time", "")
			if needed != "" and needed != Game.state.time_of_day:
				_show_system_dialogue(target["closed_title"], [target["closed_text"]], [
					{"text": target["wait_choice"], "action": "wait_and_enter", "arg": "%s|%s|%s" % [needed, target["target"], target["spawn"]]},
					{"text": "그만두기", "action": "close"},
				])
			else:
				enter_location(target["target"], target["spawn"])
		"sign":
			_show_system_dialogue(target["title"], [target["text"]], [])
		"poker_table":
			open_poker_setup(str(target.get("mode", "homegame")), "", bool(target.get("pick_opponent", false)))
		"home_edit":
			open_home_edit()
		"rest":
			_open_rest()
		"job_board":
			_open_job_board()
		"job_pickup":
			_collect_job_spot(target["id"])
		"object":
			open_object(target)


# --- dialogue ------------------------------------------------------------------

func open_npc_dialogue(npc_id: String) -> void:
	_dialogue_npc = npc_id
	var entry: Dictionary = Game.resolve_entry(npc_id, world.location_id)
	if entry.is_empty():
		entry = {"id": "", "lines": ["…(고개를 끄덕인다)"], "choices": [{"text": "안녕", "action": "close"}]}
	_show_entry(entry)


## World objects: data dialogue first (story spots), then built-in panels (projects, home, festival...).
func open_object(target: Dictionary) -> void:
	var id: String = target["id"]
	_dialogue_npc = "obj:" + id
	var entry: Dictionary = Game.resolve_entry(_dialogue_npc, world.location_id)
	if not entry.is_empty():
		_show_entry(entry)
		return
	# Built-in panels: a task that ends here (hand-over, episode choice) is offered first.
	var tasks: Array = Game.entry_choices({}, _dialogue_npc, world.location_id)
	if not tasks.is_empty():
		tasks.insert(tasks.size() - 1, {"text": "%s 보기" % str(target.get("title", target.get("prompt", "그대로"))), "action": "object_default", "arg": id})
		_show_lines(_dialogue_npc, ["여기서 할 일이 있어요."], tasks)
		return
	_open_object_panel(id, target)


func _open_object_panel(id: String, target: Dictionary) -> void:
	match id:
		"project_board":
			_open_project_board()
		"home_blueprint":
			_open_home_blueprint()
		"shop_shelves":
			_open_shelving()
		"swap_stall":
			_open_swap_stall()
		"square_mix_table", "tea_social_table":
			open_poker_setup("social_mix")
		"festival_booth":
			_open_festival()
		_:
			_show_system_dialogue(str(target.get("title", "")), ["특별한 것은 보이지 않아요."], [])


func _show_entry(entry: Dictionary) -> void:
	last_entry_id = str(entry.get("id", ""))
	var effects: Array = []
	for f in entry.get("set_flags", []):
		effects.append({"type": "flag", "flag": f})
	effects.append_array(entry.get("effects", []))
	if not effects.is_empty() or entry.get("once", false):
		var key := DialogueResolver.once_key(entry) if entry.get("once", false) else ""
		Game.run_effects(effects, key)
	var vars := Game.text_vars()
	var lines: Array = []
	for l in entry.get("lines", []):
		lines.append(DialogueResolver.format_line(l, vars))
	var choices: Array = Game.entry_choices(entry, _dialogue_npc, world.location_id)
	for c in choices:
		c["text"] = DialogueResolver.format_line(str(c["text"]), vars)
	set_mode("dialogue")
	dialogue.show_dialogue(Game.speaker_name(_dialogue_npc) if _dialogue_npc != "" else "", lines, choices)


## Dialogue box for objects (signs, doors, bed, board) rather than residents.
func _show_system_dialogue(title_text: String, lines: Array, choices: Array) -> void:
	_dialogue_npc = ""
	last_entry_id = ""
	var vars := Game.text_vars()
	var formatted: Array = []
	for l in lines:
		formatted.append(DialogueResolver.format_line(str(l), vars))
	set_mode("dialogue")
	dialogue.show_dialogue(title_text, formatted, choices)


## Lines spoken by a specific resident without a data entry (quest offers, thanks).
func _show_lines(speaker: String, lines: Array, choices: Array) -> void:
	var title_text := Game.speaker_name(speaker)
	_show_system_dialogue(title_text, lines, choices)
	_dialogue_npc = speaker


func _on_dialogue_choice_picked(c: Dictionary) -> void:
	var effects: Array = c.get("effects", [])
	if not effects.is_empty():
		var r: Dictionary = Game.run_effects(effects, str(c.get("once_key", "")))
		if not r["ok"]:
			hud.show_toast("칩이 %d개 부족해요." % int(r.get("need", 0)))
			_back_to_world()
			return
	var action := str(c.get("action", "close"))
	var arg := str(c.get("arg", ""))
	match action:
		"start_poker":
			if arg == "":
				open_poker()
			else:
				open_poker_setup(arg.get_slice("|", 0), arg.get_slice("|", 1))
		"open_shop":
			open_shop(arg)
		"dialogue":
			_show_entry(DialogueResolver.find(Game.data.dialogue, arg))
		"quest_offer":
			_show_quest_offer(arg)
		"accept_quest":
			if Game.accept_quest(arg):
				var q: Dictionary = Game.data.quests[arg]
				hud.show_toast(("의뢰를 맡았어요: " if q.get("kind", "quest") == "quest" else "이야기 시작: ") + str(q["name"]))
			_back_to_world()
		"complete_quest":
			_complete_quest(arg)
		"job_deliver":
			var jr: Dictionary = Game.job_step("deliver", _dialogue_npc)
			if jr["ok"]:
				hud.show_toast("편지 전달 완료! 보수 칩 +%d" % int(jr["reward"]))
				_show_lines(_dialogue_npc, ["편지 고마워요! 잘 받았어요."], [])
				return
			_back_to_world()
		"fund_project":
			var fr: Dictionary = Game.fund_project(arg)
			if fr["ok"]:
				hud.show_toast("공공사업 완료: " + str(Game.data.projects[arg]["name"]))
				var done_text: String = Game.data.projects[arg].get("done_text", "")
				if done_text != "":
					_show_system_dialogue(str(Game.data.projects[arg]["name"]), [done_text], [])
					return
			else:
				hud.show_toast("칩이 %d개 부족해요." % int(fr.get("need", 0)) if fr.get("reason", "") == "not_enough_chips" else "지금은 후원할 수 없어요.")
			_back_to_world()
		"upgrade_home":
			var hr: Dictionary = Game.upgrade_home()
			if hr["ok"]:
				hud.show_toast("집을 넓혔어요!")
				enter_location(world.location_id, "default", world.player.position, "집이 넓어졌어요")
				return
			hud.show_toast("칩이 %d개 부족해요." % int(hr.get("need", 0)) if hr.get("reason", "") == "not_enough_chips" else "아직 조건이 맞지 않아요.")
			_back_to_world()
		"start_job":
			if Game.start_job(arg):
				hud.show_toast(str(Game.data.jobs[arg].get("start_toast", "아르바이트를 시작했어요!")))
			_back_to_world()
		"shelve":
			_shelve(arg)
		"trade":
			var tr: Dictionary = Game.trade(arg)
			hud.show_toast("교환했어요!" if tr["ok"] else "교환에 필요한 물건이 없어요.")
			_back_to_world()
		"set_time":
			_change_time(arg)
		"wait_and_enter":
			var parts := arg.split("|")
			Game.set_time(parts[0])
			enter_location(parts[1], parts[2])
		"poker_loadout":
			_start_poker_with(arg)
		"object_default":
			var obj: Dictionary = world.find_interactable("object", arg)
			_open_object_panel(arg, obj)
		"board":
			_open_board_page(arg)
		"effects":
			if c.has("next"):
				_show_entry(DialogueResolver.find(Game.data.dialogue, c["next"]))
				return
			_back_to_world()
		_:
			if c.has("next"):
				_show_entry(DialogueResolver.find(Game.data.dialogue, c["next"]))
				return
			_back_to_world()


func _show_quest_offer(quest_id: String) -> void:
	var q: Dictionary = Game.data.quests[quest_id]
	var accept_text := str(q.get("accept_text", "맡을게요" if q.get("kind", "quest") == "quest" else "좋아요"))
	_show_lines(str(q["giver"]), q.get("offer_lines", ["부탁이 있어요."]), [
		{"text": accept_text, "action": "accept_quest", "arg": quest_id},
		{"text": "다음에요", "action": "close"},
	])


func _complete_quest(arg: String) -> void:
	var quest_id := arg.get_slice("|", 0)
	var q: Dictionary = Game.data.quests.get(quest_id, {})
	var result: Dictionary = Game.complete_quest(arg)
	if not result["ok"]:
		_back_to_world()
		return
	if int(result["reward"]) > 0:
		hud.show_toast("의뢰 완료! 칩 +%d" % int(result["reward"]))
	else:
		hud.show_toast("%s — 완료" % str(q.get("name", "")))
	var thanks: String = q.get("complete_dialogue", "")
	if thanks != "":
		_show_entry(DialogueResolver.find(Game.data.dialogue, thanks))
		return
	var lines: Array = []
	var option: Dictionary = result.get("option", {})
	lines.append_array(option.get("response", []))
	lines.append_array(q.get("thanks_lines", []))
	if not lines.is_empty():
		var speaker := str(q["target"])
		_show_lines(speaker if Game.data.npcs.has(speaker) else "obj:" + speaker, lines, [])
		return
	_back_to_world()


# --- time, rest and odd jobs ------------------------------------------------------

func _open_rest() -> void:
	if Game.state.time_of_day == "day":
		_show_system_dialogue("침대", ["포근한 침대예요. 저녁까지 푹 쉴까요?"], [
			{"text": "저녁까지 쉬기 (시간이 저녁으로 바뀌어요)", "action": "set_time", "arg": "evening"},
			{"text": "그만두기", "action": "close"},
		])
	else:
		_show_system_dialogue("침대", ["하루를 마무리할 시간이에요. 아침까지 잘까요?"], [
			{"text": "아침까지 자기 (시간이 낮으로 바뀌어요)", "action": "set_time", "arg": "day"},
			{"text": "그만두기", "action": "close"},
		])


## Changes the time of day and reloads the current place so lighting and residents follow.
func _change_time(time: String) -> void:
	Game.set_time(time)
	var pos: Vector2 = world.player.position
	enter_location(world.location_id, "default", pos, "저녁이 되었어요" if time == "evening" else "아침이 밝았어요")


## The square notice board: odd jobs, requests, village news, festival.
func _open_job_board() -> void:
	if Game.job != null:
		_show_system_dialogue("마을 게시판", ["아르바이트 진행 중이에요. %s" % Game.current_goal()], [])
		return
	var plaza: Dictionary = Game.data.jobs["job.plaza_cleanup"]
	var lines: Array = [
		"[%s] %s" % [plaza["name"], plaza["description"]],
		"몇 번이든 다시 할 수 있어요. 광장을 벗어나면 정리를 그만둔 것으로 처리돼요.",
	]
	_show_system_dialogue("마을 게시판", lines, [
		{"text": "광장 정리 아르바이트 시작하기", "action": "start_job", "arg": "job.plaza_cleanup"},
		{"text": "다른 아르바이트 보기", "action": "board", "arg": "jobs"},
		{"text": "주민들의 부탁 보기", "action": "board", "arg": "requests"},
		{"text": "마을 소식 보기", "action": "board", "arg": "news"},
		{"text": "포커 연습 한 판 (칩 없이)", "action": "start_poker", "arg": "practice|"},
		{"text": "다음에 하기", "action": "close"},
	])


func _open_board_page(page: String) -> void:
	var lines: Array = []
	match page:
		"jobs":
			for jid in Game.data.jobs:
				var j: Dictionary = Game.data.jobs[jid]
				lines.append("· %s — 보수 %d칩, 시작: %s" % [j["name"], int(j["reward"]), j.get("start_hint", "")])
		"requests":
			for qid in Game.data.quest_order:
				if not Game.data.is_quest(qid):
					continue
				var q: Dictionary = Game.data.quests[qid]
				var st := QuestBook.state_of(Game.state, qid)
				if st == QuestBook.ACTIVE:
					lines.append("▶ %s — 진행 중 (%s)" % [q["name"], Game.npc_where_text(str(q["target"]))])
				elif Game.quest_available(qid):
					lines.append("· %s — %s" % [q["name"], Game.npc_where_text(str(q["giver"]))])
			if lines.is_empty():
				lines.append("지금 새로 들어온 부탁은 없어요.")
		"news":
			lines.append(Game.story_news())
	_show_system_dialogue("마을 게시판", ["\n".join(lines)], [{"text": "닫기", "action": "close"}])


func _collect_job_spot(spot_id: String) -> void:
	var result: Dictionary = Game.collect_job_spot(spot_id)
	if not result["ok"]:
		return
	if result["done"]:
		hud.show_toast("아르바이트 완료! 보수 칩 +%d" % int(result["reward"]))
	else:
		hud.show_toast("%d / %d" % [int(result["collected"]), int(result["total"])])


func _open_shelving() -> void:
	if Game.job == null or Game.job.job_type != "shelve":
		var jd: Dictionary = Game.data.jobs["job.shop_shelving"]
		_show_system_dialogue("잡화점 선반", [jd["description"]], [
			{"text": "선반 정리 시작하기", "action": "start_job", "arg": "job.shop_shelving"},
			{"text": "다음에 하기", "action": "close"},
		])
		return
	var need: String = Game.job.next_shelf_good()
	var shelf := Game.job.done_count() + 1
	var goods: Array = Game.data.jobs["job.shop_shelving"]["goods"].duplicate()
	var choices: Array = []
	for g in goods:
		choices.append({"text": str(g), "action": "shelve", "arg": str(g)})
	choices.append({"text": "잠깐 쉬기 (나중에 이어서)", "action": "close"})
	_show_system_dialogue("잡화점 선반", ["%d번 칸 쪽지: '%s'을(를) 놓아 주세요." % [shelf, need]], choices)


func _shelve(good: String) -> void:
	var r: Dictionary = Game.job_step("shelve", good)
	if r.get("wrong", false):
		hud.show_toast("쪽지와 다른 물건이에요. 다시 골라 보세요.")
		_open_shelving()
		return
	if r["ok"] and r["done"]:
		hud.show_toast("선반 정리 완료! 보수 칩 +%d" % int(r["reward"]))
		_back_to_world()
		return
	if r["ok"]:
		_open_shelving()
		return
	_back_to_world()


# --- projects, home, festival, stall ---------------------------------------------

func _open_project_board() -> void:
	var lines: Array = ["마을 공공사업이에요. 칩을 후원하면 한 번에 완료돼요. (보유 칩 %d)" % Game.state.chips_balance]
	var choices: Array = []
	for pid in Game.data.project_order:
		var p: Dictionary = Game.data.projects[pid]
		match Game.project_status(pid):
			"complete":
				lines.append("✔ %s — 완료" % p["name"])
			"available":
				choices.append({"text": "%s 후원 (%d칩)" % [p["name"], int(p["cost"])], "action": "fund_project", "arg": pid})
			_:
				lines.append("· %s — %s" % [p["name"], p.get("locked_hint", "아직 준비 중")])
	choices.append({"text": "닫기", "action": "close"})
	_show_system_dialogue("마을 공공사업", ["\n".join(lines)], choices)


func _open_home_blueprint() -> void:
	var next: Dictionary = Game.home_stage_def(Game.state.home_stage + 1)
	var cur: Dictionary = Game.home_stage_def(Game.state.home_stage)
	var lines: Array = ["지금 집: %s" % cur.get("name", "작은 방")]
	var choices: Array = []
	if next.is_empty():
		lines.append("더 넓힐 수 있는 곳은 없어요. 모든 방이 준비됐어요.")
	else:
		lines.append("다음 단계: %s — %d칩. %s" % [next["name"], int(next["cost"]), next.get("desc", "")])
		if Conditions.check(next.get("unlock", {}), Game.state):
			choices.append({"text": "%s로 넓히기 (%d칩)" % [next["name"], int(next["cost"])], "action": "upgrade_home"})
		else:
			lines.append("조건: " + str(next.get("unlock_hint", "")))
	choices.append({"text": "닫기", "action": "close"})
	_show_system_dialogue("집 확장 설계도", ["\n".join(lines)], choices)


func _open_swap_stall() -> void:
	var choices: Array = [{"text": "카드 뒷면·칩 장식 사기", "action": "open_shop", "arg": "swap_shop"}]
	for t in Game.data.trades:
		if Game.state.events_done.has("trade:" + str(t["id"])):
			continue
		var give_name := str(Game.data.items[t["give"]]["name"])
		var get_name := str(Game.data.items[t["get"]]["name"])
		choices.append({"text": "교환: %s → %s" % [give_name, get_name], "action": "trade", "arg": t["id"]})
	choices.append({"text": "닫기", "action": "close"})
	_show_system_dialogue("작은 교환대", ["중복된 물건을 정해진 물건과 바꿀 수 있어요. 칩이나 현금으로 바꿔 주지는 않아요."], choices)


## Poker entry points (05_poker/01): pick the table's mode, an opponent where the mode lets you
## choose, then one ability if more than one is unlocked. Every mode uses the same rule engine.
func open_poker_setup(mode: String, opponent: String = "", pick_opponent: bool = false) -> void:
	var def: Dictionary = Game.poker_mode(mode)
	if def.is_empty():
		mode = "homegame"
		def = Game.poker_mode(mode)
	if not Conditions.check(def.get("unlock", {}), Game.state, world.location_id):
		_show_system_dialogue(str(def.get("name", "포커")), [str(def.get("locked_text", "아직 열리지 않았어요."))], [])
		return
	if not Game.can_join_poker(mode):
		hud.show_toast("참가금 칩 %d개가 필요해요. 광장 아르바이트로 모을 수 있어요." % Game.poker_stake(mode))
		_back_to_world()
		return
	if mode == "tournament":
		opponent = Game.tournament_opponent()
	if opponent == "" and (pick_opponent or def.has("opponents")):
		var choices: Array = []
		for npc in Game.poker_opponents(mode):
			var persona := str(Game.data.opponents[npc].get("context", ""))
			choices.append({"text": "%s와 한 판 (%s)" % [Game.data.npc_name(npc), persona], "action": "poker_loadout", "arg": "%s|%s|" % [mode, npc]})
		if choices.is_empty():
			_show_system_dialogue(str(def["name"]), ["아직 함께 칠 주민이 없어요. 마을 사람들과 먼저 인사해 보세요."], [])
			return
		choices.append({"text": "그만두기", "action": "close"})
		_show_system_dialogue(str(def["name"]), [str(def.get("desc", ""))], choices)
		return
	_start_poker_with("%s|%s|" % [mode, opponent])


## arg "mode|opponent|ability": asks for the ability when several are unlocked, then deals.
func _start_poker_with(arg: String) -> void:
	var parts := arg.split("|")
	var mode := parts[0]
	var opponent := parts[1] if parts.size() > 1 else ""
	var ability := parts[2] if parts.size() > 2 else ""
	if ability == "" and Game.state.abilities_unlocked.size() > 1:
		var choices: Array = []
		for aid in Game.state.abilities_unlocked:
			var a: Dictionary = Game.data.abilities.get(aid, {})
			if not a.is_empty():
				choices.append({"text": "%s — %s" % [a["name"], a.get("description", "")], "action": "poker_loadout", "arg": "%s|%s|%s" % [mode, opponent, aid]})
		choices.append({"text": "그만두기", "action": "close"})
		_show_system_dialogue("가져갈 능력 고르기", ["한 판에 능력 하나를 가져갈 수 있어요. 능력은 승패를 정하지 않아요."], choices)
		return
	var m: PokerMatch = Game.create_poker_match(mode, opponent, ability)
	if m == null:
		hud.show_toast("지금은 자리에 앉을 수 없어요.")
		_back_to_world()
		return
	set_mode("poker")
	hud.visible = false
	poker.start(m, _spectators(m))


## Residents standing at this place who watch a social-mix hand (up to two).
func _spectators(m: PokerMatch) -> Array:
	if m.mode != "social_mix" or world == null:
		return []
	var out: Array = []
	for npc in world.npc_nodes:
		if npc != m.opponent_id and out.size() < 2:
			out.append(npc)
	return out


func _open_festival() -> void:
	var entry: Dictionary = Game.resolve_entry("obj:festival_booth", world.location_id)
	if not entry.is_empty():
		_dialogue_npc = "obj:festival_booth"
		_show_entry(entry)
		return
	_show_system_dialogue("축제 부스", ["축제 준비가 한창이에요. 게시판에서 마을 소식을 확인해 보세요."], [])


# --- activities ----------------------------------------------------------------

## The card-room home game against the regular (first-play path: Moa's and Lumi's invitation).
func open_poker() -> void:
	open_poker_setup("homegame")


func _on_poker_exit() -> void:
	poker.visible = false
	hud.visible = true
	_back_to_world()


func open_shop(shop_id: String) -> void:
	set_mode("shop")
	shop.open(shop_id)


func open_home_edit() -> void:
	set_mode("home_edit")
	hud.set_prompt({})
	home_edit.open(world)


func open_menu() -> void:
	if ui_mode != "world":
		return
	set_mode("menu")
	menu.open()


func _back_to_world() -> void:
	for screen in [menu]:
		screen.visible = false
	if world:
		world.refresh_markers()
		world.player.queue_redraw()
	hud.refresh()
	set_mode("world")


func _on_hud_interact() -> void:
	if world and ui_mode == "world":
		world.try_interact()


func _on_focus_changed(target: Dictionary) -> void:
	if ui_mode == "world":
		hud.set_prompt(target)


func _on_state_changed() -> void:
	if hud.visible:
		hud.refresh()


func _on_tutorial_finished() -> void:
	if Game.state:
		Game.apply_flags(["tutorial_done"])


func _unhandled_input(event: InputEvent) -> void:
	if ui_mode == "world" and event.is_action_pressed("menu"):
		open_menu()
		get_viewport().set_input_as_handled()


# --- automated end-to-end run --------------------------------------------------

func _maybe_start_e2e() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--e2e="):
			var scenario := arg.get_slice("=", 1)
			var script_path := "res://tests/e2e/content_e2e.gd" if scenario.begins_with("cc") or scenario in ["story", "life"] else "res://tests/e2e/first_play_e2e.gd"
			var driver: Node = load(script_path).new()
			driver.main = self
			add_child(driver)
			driver.run.call_deferred(arg.get_slice("=", 1))
			return
