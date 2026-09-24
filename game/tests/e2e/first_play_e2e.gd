extends Node
## End-to-end first-play driver (spec v0.2 P0-P8, Gate 1).
## Runs inside the real game (Main scene + Game autoload). Movement and interaction use real
## input actions; buttons and cards are triggered through the same signals a mouse click emits.
## Exits with code 0 when every check passed, 1 otherwise.
##   godot --headless --path game -- --e2e=<scenario> --save-path=user://e2e.json [--shots=<abs dir>]
## Scenarios: win, draw, lose (full loop per poker outcome), resume_a/b/c (three separate
## processes: quit mid-game, continue, continue again), reject (unreadable saves).

const DECKS := {
	# Deal order is player, opponent, player, ... then draws. See tests/unit/test_poker_match.gd.
	"win": ["AS", "QS", "AH", "QH", "KD", "9D", "7C", "5C", "2S", "3H", "6H", "4D", "8S", "JC"],
	"draw": ["KS", "KD", "KH", "KC", "9C", "9H", "7D", "7S", "4S", "4H", "9D", "7H", "4C"],
	"lose": ["2C", "AH", "5D", "AC", "8H", "6S", "JS", "9C", "3D", "TD", "4S", "7C", "KH"],
}
const EXPECTED_FIRST := {"win": 100, "draw": 70, "lose": 60}
const LAMP := "furniture.lamp_small"

var main: Node
var _failures: Array = []
var _checks := 0
var _shots_dir := ""
var _scenario := ""


func run(scenario: String) -> void:
	_scenario = scenario
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots_dir = arg.get_slice("=", 1)
	print("[e2e] scenario=%s save=%s" % [scenario, Game.save_path])
	await _frames(5)
	match scenario:
		"win", "draw", "lose":
			await _first_play(scenario)
		"resume_a":
			await _resume_a()
		"resume_b":
			await _resume_b()
		"resume_c":
			await _resume_c()
		"reject":
			await _reject()
		_:
			_check(false, "unknown scenario " + scenario)
	_finish()


# --- scenarios -------------------------------------------------------------------

func _first_play(outcome: String) -> void:
	SaveSystem.delete(Game.save_path)
	main.show_title()
	await _frames(3)
	_check(main.ui_mode == "title", "P0 title shown")
	_check(main.title.continue_button.disabled, "P0 continue disabled without a save")

	# P0 new game with a name
	main.title.new_game_button.pressed.emit()
	await _frames(2)
	main.title.name_edit.text = "테스터"
	main.title.start_button.pressed.emit()
	await _wait_world("village_square")
	_check_eq(Game.state.player_name, "테스터", "P0 player name")
	_check_eq(Game.state.chips_balance, 0, "P0 starting chips")
	_check(main.tutorial.visible and main.tutorial.step == 1, "P0 tutorial step 1 (move)")
	_check(main.hud._goal_label.text.contains("루미에게 인사"), "P0 goal points to Lumi")

	# movement and collision with real input
	var start: Vector2 = main.world.player.position
	Input.action_press("move_up")
	await _physics(24)
	Input.action_release("move_up")
	_check(main.world.player.position.distance_to(start) > 60.0, "P0 player moves with input")
	_check_eq(main.tutorial.step, 2, "P0 tutorial advances to step 2 (talk)")
	main.world.player.position = Vector2(260, 380)
	await _physics(2)
	Input.action_press("move_up")
	await _physics(40)
	Input.action_release("move_up")
	_check(main.world.player.position.y >= 362.0, "P0 building blocks movement (y=%.1f)" % main.world.player.position.y)

	# P1 greet Lumi
	await _go_to("npc", "npc_lumi")
	_check(main.hud.prompt_text().contains("루미"), "P1 prompt shows Lumi")
	_check(main.world.npc_nodes["npc_lumi"].show_marker, "P1 Lumi shows the new-dialogue marker")
	await _shot("01_village")
	await _press("interact")
	_check_eq(main.ui_mode, "dialogue", "P1 dialogue opens")
	_check_eq(main.last_entry_id, "lumi_intro", "P1 first meeting dialogue")
	_check(main.dialogue.current_line().contains("테스터"), "P1 Lumi uses the player's name")
	_check_eq(main.tutorial.step, 0, "P0 tutorial finished after first interaction")
	_check(Game.state.get_flag("tutorial_done"), "P0 tutorial flag saved")
	await _read_to_choices()
	await _choose("dialogue")
	_check_eq(main.last_entry_id, "lumi_poker_info", "P2 poker info reachable from Lumi's menu")
	await _read_to_choices()
	await _choose("close")
	_check_eq(main.ui_mode, "world", "P1 back to world")
	_check(Game.state.get_flag("intro_met_lumi"), "P1 intro flag set")
	_check(_saved().get("flags", {}).get("intro_met_lumi", false), "P1 intro flag saved to disk")
	_check(not main.world.npc_nodes["npc_lumi"].show_marker, "P1 marker cleared")
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_before_poker", "P1 repeat dialogue differs from the first")
	await _close_dialogue()
	_check(main.hud._goal_label.text.contains("포커 모임"), "P2 goal points to poker")

	# P2 shop before poker: browsing allowed, buying blocked by chips
	await _enter("door", "shop_building", "small_shop")
	await _talk("npc_sera")
	_check_eq(main.last_entry_id, "sera_first", "P2 Sera greets")
	await _read_to_choices()
	await _choose("open_shop")
	_check_eq(main.ui_mode, "shop", "P2 shop opens")
	var buy: Button = main.shop.buy_buttons[LAMP]
	_check(buy.disabled and buy.text.contains("칩 부족"), "P2 lamp not affordable at 0 chips (%s)" % buy.text)
	main.shop.close_button.pressed.emit()
	await _frames(2)
	_check_eq(main.ui_mode, "world", "P2 shop closes")
	await _enter("door", "exit_shop", "village_square")

	# P2 signs
	await _go_to("sign", "sign_card_room")
	await _press("interact")
	_check(main.dialogue.current_line().contains("포커 모임"), "P2 card room notice readable")
	await _press("interact")
	_check_eq(main.ui_mode, "world", "P2 sign closes")

	# P3 evening gathering
	await _enter("door", "card_room_building", "card_room")
	_check(main.world.is_evening(), "P3 card room uses evening lighting")
	await _shot("02_card_room", 170)
	await _talk("npc_moa")
	_check_eq(main.last_entry_id, "moa_first", "P3 Moa explains the rules")
	await _read_to_choices()
	Game.debug_deck_queue = [DECKS[outcome], DECKS["lose"]]
	await _choose("start_poker")
	_check_eq(main.ui_mode, "poker", "P3 poker starts from Moa's menu")
	_check_eq(main._caption.modulate.a, 0.0, "P3 location caption never covers the poker table")

	# P4 the hand
	var poker = main.poker
	for v in poker.opponent_views:
		_check(v.card == null, "P4 opponent card hidden before showdown")
	_check(poker.player_views[0].card != null, "P4 player cards shown")
	poker.ability_button.pressed.emit()
	await _frames(1)
	_check(poker._ability_label.text.contains("원페어 이상"), "P4 Star Sense answers pair-or-better")
	_check(poker.ability_button.disabled, "P4 Star Sense used up")
	for v in poker.opponent_views:
		_check(v.card == null, "P4 opponent still hidden after Star Sense")
	if outcome == "win":
		poker.player_views[4].pressed.emit(4)
		await _frames(1)
		_check(poker.draw_button.text.contains("1장"), "P4 one card selected")
		await _shot("02_poker")
		poker.draw_button.pressed.emit()
	else:
		await _shot("02_poker")
		poker.stand_button.pressed.emit()
	await _frames(2)

	# P5 payout
	_check_eq(poker.match_ref.outcome, {"win": 1, "draw": 0, "lose": -1}[outcome], "P5 outcome " + outcome)
	_check_eq(Game.state.chips_balance, EXPECTED_FIRST[outcome], "P5 chips after first hand")
	_check_eq(int(poker.last_result["bonus"]), 40, "P5 first-play bonus paid")
	_check(Game.state.get_flag("first_poker_bonus_claimed"), "P5 bonus flag")
	_check(poker._result_panel.visible, "P5 result shown")
	for v in poker.opponent_views:
		_check(v.card != null, "P5 opponent cards revealed at showdown")
	_check_ledger()
	_check_eq(int(_saved().get("chips_balance", -1)), EXPECTED_FIRST[outcome], "P5 payout saved")
	await _shot("02_poker_result")
	poker.again_button.pressed.emit()
	await _frames(2)
	_check_eq(poker.match_ref.phase, PokerMatch.Phase.DRAW, "P8 another hand starts")
	poker.stand_button.pressed.emit()
	await _frames(2)
	_check_eq(int(poker.last_result["bonus"]), 0, "P5 no second bonus")
	var after_two: int = EXPECTED_FIRST[outcome] + 20
	_check_eq(Game.state.chips_balance, after_two, "P5 second hand pays base only")
	_check_eq(Game.state.poker_hands_completed, 2, "P5 two hands counted")
	poker.result_leave_button.pressed.emit()
	await _frames(2)
	_check_eq(main.ui_mode, "world", "P5 back to the card room")
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_cardroom_default", "P3 Lumi at the table offers a hand")
	await _read_to_choices()
	await _choose("close")
	await _enter("door", "exit_card_room", "village_square")
	_check(not main.world.is_evening(), "P8 village is free-roam daytime again")

	# P6 buy the lamp
	await _enter("door", "shop_building", "small_shop")
	await _talk("npc_sera")
	_check_eq(main.last_entry_id, "sera_default", "P6 Sera repeat line")
	await _read_to_choices()
	await _choose("open_shop")
	buy = main.shop.buy_buttons[LAMP]
	_check(not buy.disabled, "P6 lamp affordable")
	buy.pressed.emit()
	await _frames(2)
	_check_eq(Game.state.chips_balance, after_two - 50, "P6 lamp costs 50")
	_check_eq(Game.state.owned_count(LAMP), 1, "P6 lamp in storage")
	_check(Game.state.collection.has(LAMP), "P7 lamp recorded in collection")
	_check_ledger()
	main.shop.close_button.pressed.emit()
	await _frames(2)
	await _enter("door", "exit_shop", "village_square")
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_lamp_not_placed", "P6 Lumi hints how to place the lamp")
	await _read_to_choices()
	await _choose("close")

	# P6 place it at home
	await _enter("door", "home_building", "player_home")
	await _go_to("home_edit", "home_decorate")
	await _press("interact")
	_check_eq(main.ui_mode, "home_edit", "P6 decorate mode opens")
	var edit = main.home_edit
	_check(edit.item_buttons.has(LAMP), "P6 lamp listed in storage")
	edit.item_buttons[LAMP].pressed.emit()
	await _frames(1)
	edit.slot_buttons["slot_window"].pressed.emit()
	await _frames(1)
	_check(not edit.confirm_button.disabled, "P6 confirm enabled with item and empty slot")
	await _shot("03_housing_preview")
	edit.confirm_button.pressed.emit()
	await _frames(2)
	_check_eq(Game.state.placement_at("slot_window"), LAMP, "P6 lamp placed by the window")
	_check_eq(Game.state.owned_count(LAMP), 0, "P6 storage empty")
	_check_eq(Game.state.chips_balance, after_two - 50, "P6 placing costs nothing")
	var saved_places: Array = _saved().get("home_placements", [])
	_check(saved_places.size() == 1 and saved_places[0]["slot"] == "slot_window", "P6 placement saved to disk")
	await _shot("03_housing")
	edit.close_button.pressed.emit()
	await _frames(2)
	_check_eq(main.ui_mode, "world", "P6 decorate mode closes")
	await _enter("door", "exit_home", "village_square")
	await _enter("door", "home_building", "player_home")
	_check_eq(Game.state.placement_at("slot_window"), LAMP, "P6 lamp still there after re-entering")
	await _enter("door", "exit_home", "village_square")

	# P7 Lumi remembers
	_check(main.world.npc_nodes["npc_lumi"].show_marker, "P7 Lumi has something new to say")
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_lamp_reaction", "P7 Lumi reacts to the lamp")
	_check(main.dialogue.current_line().contains("불빛"), "P7 reaction mentions the light")
	await _read_to_choices()
	await _choose("close")
	_check(Game.state.get_flag("lumi_lamp_reaction_seen"), "P7 reaction flag")
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_after_lamp", "P7 follow-up line differs")
	await _read_to_choices()
	await _choose("close")
	_check(main.hud._goal_label.text.contains("자유롭게"), "P8 goal is free play")

	# collection book via the menu
	await _press("menu")
	_check_eq(main.ui_mode, "menu", "P8 menu opens with Esc")
	main.menu.collection_button.pressed.emit()
	await _frames(1)
	_check(main.menu.collection_text().contains("작은 등불") and main.menu.collection_text().contains("1 / 1"), "P7 collection shows the lamp: " + main.menu.collection_text())
	main.menu.show_main()

	# P8 save, back to title, continue
	var chips_before: int = Game.state.chips_balance
	main.menu.title_button.pressed.emit()
	await _frames(3)
	_check_eq(main.ui_mode, "title", "P8 back at title")
	_check(not main.title.continue_button.disabled, "P8 continue available")
	main.title.continue_button.pressed.emit()
	await _wait_world("village_square")
	_check_eq(Game.state.chips_balance, chips_before, "P8 chips restored")
	_check_eq(Game.state.placement_at("slot_window"), LAMP, "P8 placement restored")
	_check(Game.state.get_flag("lumi_lamp_reaction_seen"), "P8 flags restored")


func _resume_a() -> void:
	SaveSystem.delete(Game.save_path)
	main.show_title()
	await _frames(2)
	main.title.new_game_button.pressed.emit()
	await _frames(1)
	main.title.name_edit.text = "재개"
	main.title.start_button.pressed.emit()
	await _wait_world("village_square")
	# Go to the gathering before meeting anyone: Lumi introduces herself there.
	await _enter("door", "card_room_building", "card_room")
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_intro_cardroom", "alt order: Lumi introduces herself at the card room")
	await _read_to_choices()
	Game.debug_deck_queue = [DECKS["lose"]]
	await _choose("start_poker")
	_check_eq(main.ui_mode, "poker", "alt order: poker from Lumi's invitation")
	main.poker.stand_button.pressed.emit()
	await _frames(2)
	_check_eq(Game.state.chips_balance, 60, "loss + bonus = 60")
	main.poker.again_button.pressed.emit()
	await _frames(2)
	_check_eq(main.poker.match_ref.phase, PokerMatch.Phase.DRAW, "second hand in progress")
	var saved := _saved()
	_check_eq(int(saved.get("chips_balance", -1)), 60, "saved chips before abrupt quit")
	_check_eq(int(saved.get("poker_hands_completed", -1)), 1, "unfinished hand not counted")
	print("[e2e] quitting mid-hand without saving (simulated force close)")


func _resume_b() -> void:
	await _frames(2)
	_check(not main.title.continue_button.disabled, "continue enabled")
	main.title.continue_button.pressed.emit()
	await _wait_world("card_room")
	_check_eq(Game.state.chips_balance, 60, "chips restored after abrupt quit")
	_check(Game.state.get_flag("first_poker_bonus_claimed"), "bonus flag restored")
	_check_eq(Game.state.poker_hands_completed, 1, "hand count restored")
	await _go_to("poker_table", "poker_table")
	Game.debug_deck_queue = [DECKS["lose"]]
	await _press("interact")
	_check_eq(main.ui_mode, "poker", "poker from the table")
	main.poker.stand_button.pressed.emit()
	await _frames(2)
	_check_eq(int(main.poker.last_result["bonus"]), 0, "no duplicate bonus after resume")
	_check_eq(Game.state.chips_balance, 80, "80 after second loss")
	main.poker.result_leave_button.pressed.emit()
	await _frames(2)
	await _enter("door", "exit_card_room", "village_square")
	await _enter("door", "shop_building", "small_shop")
	await _talk("npc_sera")
	await _read_to_choices()
	await _choose("open_shop")
	main.shop.buy_buttons[LAMP].pressed.emit()
	await _frames(1)
	main.shop.close_button.pressed.emit()
	await _frames(1)
	_check_eq(Game.state.chips_balance, 30, "lamp bought")
	await _enter("door", "exit_shop", "village_square")
	await _enter("door", "home_building", "player_home")
	await _go_to("home_edit", "home_decorate")
	await _press("interact")
	main.home_edit.item_buttons[LAMP].pressed.emit()
	main.home_edit.slot_buttons["slot_table"].pressed.emit()
	main.home_edit.confirm_button.pressed.emit()
	await _frames(1)
	main.home_edit.close_button.pressed.emit()
	await _frames(1)
	_check_eq(Game.state.placement_at("slot_table"), LAMP, "lamp on the table")
	await _press("menu")
	main.menu.save_button.pressed.emit()
	await _frames(1)
	_check(main.menu._status.text.contains("저장했어요"), "menu save confirms")


func _resume_c() -> void:
	await _frames(2)
	main.title.continue_button.pressed.emit()
	await _wait_world("player_home")
	_check_eq(Game.state.chips_balance, 30, "chips after restart")
	_check_eq(Game.state.placement_at("slot_table"), LAMP, "placement after restart")
	_check_eq(Game.state.owned_count(LAMP), 0, "storage after restart")
	await _enter("door", "exit_home", "village_square")
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_lamp_reaction", "Lumi reacts after restart")


func _reject() -> void:
	var future := '{"save_version": 999, "player_name": "미래", "chips_balance": 999}'
	_write_save(future)
	main.show_title()
	await _frames(2)
	main.title.continue_button.pressed.emit()
	await _frames(2)
	_check_eq(main.ui_mode, "title", "newer save: stays on title")
	_check(main.title._message.text.contains("새로운 버전"), "newer save: message shown (%s)" % main.title._message.text)
	_check_eq(FileAccess.get_file_as_string(Game.save_path), future, "newer save: file untouched")
	_write_save("{ broken")
	main.title.continue_button.pressed.emit()
	await _frames(2)
	_check(main.title._message.text.contains("손상"), "corrupt save: message shown")
	main.title.new_game_button.pressed.emit()
	await _frames(1)
	_check(main.title._confirm_panel.visible, "new game over existing save asks first")
	main.title.overwrite_yes_button.pressed.emit()
	await _frames(1)
	main.title.name_edit.text = ""
	main.title.start_button.pressed.emit()
	await _wait_world("village_square")
	_check_eq(Game.state.player_name, Game.DEFAULT_PLAYER_NAME, "empty name uses the default")
	_check_eq(int(_saved().get("save_version", -1)), GameState.SAVE_VERSION, "fresh save written")


# --- helpers ---------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


func _approach(target: Dictionary) -> Vector2:
	var pos: Vector2 = target["pos"]
	match str(target["kind"]):
		"npc":
			if target["id"] == "npc_sera":
				return pos + Vector2(0, 112)
			if main.world.location_id == "card_room" and target["id"] == "npc_lumi":
				return pos + Vector2(60, 0)
			return pos + Vector2(0, 40)
		"door":
			return pos + (Vector2(0, -30) if main.world.loc.get("interior", false) else Vector2(0, 30))
		"sign":
			return pos + Vector2(0, 30)
	return pos + Vector2(0, 8)


## Places the player next to a target (walking there is covered by the movement checks) and
## verifies the world focuses it through its normal proximity logic.
func _go_to(kind: String, id: String) -> void:
	var target: Dictionary = main.world.find_interactable(kind, id)
	_check(not target.is_empty(), "target %s/%s exists" % [kind, id])
	if target.is_empty():
		return
	main.world.player.position = _approach(target)
	await _physics(3)
	_check_eq(main.world.focused.get("id", ""), id, "focus on " + id)


func _talk(npc_id: String) -> void:
	await _go_to("npc", npc_id)
	await _press("interact")
	_check_eq(main.ui_mode, "dialogue", "dialogue with " + npc_id)


func _read_to_choices() -> void:
	for i in 12:
		if main.dialogue.showing_choices() or not main.dialogue.visible:
			break
		await _press("interact")
	_check(main.dialogue.showing_choices(), "choices shown")


func _choose(action: String) -> void:
	var choices: Array = main.dialogue._choices
	for i in choices.size():
		if choices[i].get("action", "") == action:
			main.dialogue.choice_buttons[i].pressed.emit()
			await _frames(2)
			return
	_check(false, "choice with action %s not offered" % action)


func _close_dialogue() -> void:
	await _read_to_choices()
	await _choose("close")


func _enter(kind: String, id: String, expected_location: String) -> void:
	await _go_to(kind, id)
	await _press("interact")
	await _wait_world(expected_location)


func _wait_world(location: String) -> void:
	for i in 240:
		if main.ui_mode == "world" and main.world != null and main.world.location_id == location:
			await _physics(2)
			return
		await _frames(1)
	_check(false, "timed out waiting for %s (mode=%s)" % [location, main.ui_mode])


func _saved() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	return parsed if parsed is Dictionary else {}


func _write_save(text: String) -> void:
	var f := FileAccess.open(Game.save_path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _check_ledger() -> void:
	var total := 0
	for e in Game.state.chips_ledger:
		total += int(e["delta"])
		_check(int(e["balance"]) >= 0, "ledger balance never negative")
	_check_eq(total, Game.state.chips_balance, "ledger sums to balance")


func _shot(shot_name: String, settle_frames: int = 20) -> void:
	if _shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	await _frames(settle_frames)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s_%s.png" % [_shots_dir, _scenario, shot_name]
	img.save_png(path)
	print("[e2e] screenshot " + path)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		print("[e2e] FAIL " + message)


func _check_eq(actual, expected, message: String) -> void:
	_check(typeof(actual) == typeof(expected) and actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	print("[e2e] %s: %d checks, %d failed" % [_scenario, _checks, _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)
