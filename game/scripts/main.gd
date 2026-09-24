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


func return_to_title() -> void:
	Game.save_game()
	show_title()


func quit_game() -> void:
	if Game.state != null:
		Game.save_game()
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and Game.state != null:
		Game.save_game()


# --- locations -----------------------------------------------------------------

func enter_location(loc_id: String, spawn_key: String, spawn_position = null) -> void:
	set_mode("transition")
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
	if loc.has("caption"):
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
			enter_location(target["target"], target["spawn"])
		"sign":
			_dialogue_npc = ""
			set_mode("dialogue")
			dialogue.show_dialogue(target["title"], [target["text"]], [])
		"poker_table":
			open_poker()
		"home_edit":
			open_home_edit()


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
	set_mode("dialogue")
	dialogue.show_dialogue(Game.data.npc_name(_dialogue_npc), lines, entry.get("choices", []))


func _on_dialogue_choice(action: String, arg: String) -> void:
	match action:
		"start_poker":
			open_poker()
		"open_shop":
			open_shop(arg)
		"dialogue":
			_show_entry(DialogueResolver.find(Game.data.dialogue, arg))
		_:
			_back_to_world()


# --- activities ----------------------------------------------------------------

func open_poker() -> void:
	var m: PokerMatch = Game.create_poker_match()
	if m == null:
		hud.show_toast("참가비가 부족해요.")
		_back_to_world()
		return
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
