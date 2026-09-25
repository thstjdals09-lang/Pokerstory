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
	dialogue.choice_made.connect(_on_dialogue_choice)
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
	if Game.job != null and Game.data.jobs[Game.job.job_id].get("location", "") != loc_id:
		Game.cancel_job()
		hud.show_toast("광장을 떠나서 아르바이트를 그만뒀어요. (보수 없음)")
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
			open_poker()
		"home_edit":
			open_home_edit()
		"rest":
			_open_rest()
		"job_board":
			_open_job_board()
		"job_pickup":
			_collect_job_spot(target["id"])


# --- dialogue ------------------------------------------------------------------

func open_npc_dialogue(npc_id: String) -> void:
	var entry := DialogueResolver.resolve(Game.data.dialogue, npc_id, world.location_id, Game.state)
	_dialogue_npc = npc_id
	_show_entry(entry)


func _show_entry(entry: Dictionary) -> void:
	last_entry_id = str(entry.get("id", ""))
	Game.apply_flags(entry.get("set_flags", []))
	var vars := Game.text_vars()
	var lines: Array = []
	for l in entry.get("lines", []):
		lines.append(DialogueResolver.format_line(l, vars))
	var choices: Array = []
	for c in entry.get("choices", []):
		if Conditions.check(c.get("conditions", {}), Game.state, world.location_id):
			choices.append(c)
	set_mode("dialogue")
	dialogue.show_dialogue(Game.data.npc_name(_dialogue_npc), lines, choices)


## Dialogue box for objects (signs, doors, bed, board) rather than residents.
func _show_system_dialogue(title_text: String, lines: Array, choices: Array) -> void:
	_dialogue_npc = ""
	last_entry_id = ""
	var vars := Game.text_vars()
	var formatted: Array = []
	for l in lines:
		formatted.append(DialogueResolver.format_line(l, vars))
	set_mode("dialogue")
	dialogue.show_dialogue(title_text, formatted, choices)


func _on_dialogue_choice(action: String, arg: String) -> void:
	match action:
		"start_poker":
			open_poker()
		"open_shop":
			open_shop(arg)
		"dialogue":
			_show_entry(DialogueResolver.find(Game.data.dialogue, arg))
		"accept_quest":
			if Game.accept_quest(arg):
				hud.show_toast("의뢰를 맡았어요: " + str(Game.data.quests[arg]["name"]))
			_back_to_world()
		"complete_quest":
			var result: Dictionary = Game.complete_quest(arg)
			if result["ok"]:
				hud.show_toast("의뢰 완료! 칩 +%d" % int(result["reward"]))
				var thanks: String = Game.data.quests[arg].get("complete_dialogue", "")
				if thanks != "":
					_show_entry(DialogueResolver.find(Game.data.dialogue, thanks))
					return
			_back_to_world()
		"set_time":
			_change_time(arg)
		"wait_and_enter":
			var parts := arg.split("|")
			Game.set_time(parts[0])
			enter_location(parts[1], parts[2])
		"start_job":
			if Game.start_job(arg):
				hud.show_toast("광장에 흩어진 카드와 칩을 주워 주세요!")
			_back_to_world()
		_:
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


func _open_job_board() -> void:
	var job_def: Dictionary = Game.data.jobs.values()[0]
	if Game.job != null:
		_show_system_dialogue("아르바이트 게시판", ["정리 중이에요. 남은 카드와 칩을 마저 주워 주세요. (%d / %d)" % [Game.job.collected.size(), Game.job.total()]], [])
		return
	_show_system_dialogue("아르바이트 게시판", [
		"[%s] %s" % [job_def["name"], job_def["description"]],
		"몇 번이든 다시 할 수 있어요. 광장을 벗어나면 정리를 그만둔 것으로 처리돼요.",
	], [
		{"text": "아르바이트 시작하기", "action": "start_job", "arg": job_def["id"]},
		{"text": "다음에 하기", "action": "close"},
	])


func _collect_job_spot(spot_id: String) -> void:
	var result: Dictionary = Game.collect_job_spot(spot_id)
	if not result["ok"]:
		return
	if result["done"]:
		hud.show_toast("정리 완료! 보수 칩 +%d" % int(result["reward"]))
	else:
		hud.show_toast("정리 %d / %d" % [int(result["collected"]), int(result["total"])])


# --- activities ----------------------------------------------------------------

func open_poker() -> void:
	if not Game.can_join_poker():
		hud.show_toast("참가금 칩 %d개가 필요해요. 광장 아르바이트로 모을 수 있어요." % Game.poker_stake())
		_back_to_world()
		return
	var m: PokerMatch = Game.create_poker_match()
	set_mode("poker")
	hud.visible = false
	poker.start(m)


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
			var driver: Node = load("res://tests/e2e/first_play_e2e.gd").new()
			driver.main = self
			add_child(driver)
			driver.run.call_deferred(arg.get_slice("=", 1))
			return
