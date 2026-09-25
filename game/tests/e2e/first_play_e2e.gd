extends Node
## End-to-end driver for the first-play loop
## (spec v0.2 + Design Correction 02 + Design Review 03 / Economy v0.2.2).
## Runs inside the real game (Main scene + Game autoload). Movement and interaction use real
## input actions; buttons and cards are triggered through the same signals a mouse click emits.
## Exits with code 0 when every check passed, 1 otherwise.
##   godot --headless --path game -- --e2e=<scenario> --save-path=user://e2e.json [--shots=<abs dir>]
## Scenarios (Design Review 03, section 3):
##   path_a          new game -> poker win -> lamp -> place -> reaction
##   path_b          new game -> poker loss -> quest -> lamp -> place -> reaction
##   path_c          new game -> odd job only (no poker) -> lamp -> place
##   path_d1/d2      poker -> see hand -> forced quit / restart -> same hand resumes -> settle once
## Regression:
##   broke           fold, lose everything, blocked, recover with odd jobs, draw, win
##   migrate         version-1 save keeps chips; version-2 save with a paid stake but no cards
##   reject          unreadable saves
## Visual slice 01 (screenshots with --shots, windowed):
##   slice           the first-play path through square, card room and home, one shot per beat

const DECKS := {
	# Deal order is player, opponent, player, ... then draws. See tests/unit/test_poker_match.gd.
	"win": ["AS", "QS", "AH", "QH", "KD", "9D", "7C", "5C", "2S", "3H", "6H", "4D", "8S", "JC"],
	"draw": ["KS", "KD", "KH", "KC", "9C", "9H", "7D", "7S", "4S", "4H", "9D", "7H", "4C"],
	"lose": ["2C", "AH", "5D", "AC", "8H", "6S", "JS", "9C", "3D", "TD", "4S", "7C", "KH"],
}
const WIN_PLAYER := ["AS", "AH", "KD", "7C", "2S"]
const WIN_OPPONENT := ["QS", "QH", "9D", "5C", "3H"]
const LAMP := "furniture.lamp_small"
const QUEST := "quest.sera_delivery"

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
		"path_a":
			await _path_a()
		"path_b":
			await _path_b()
		"path_c":
			await _path_c()
		"path_d1":
			await _path_d1()
		"path_d2":
			await _path_d2()
		"broke":
			await _broke()
		"migrate":
			await _migrate()
		"reject":
			await _reject()
		"slice":
			await _slice()
		_:
			_check(false, "unknown scenario " + scenario)
	_finish()


# --- PATH A: poker win -----------------------------------------------------------

func _path_a() -> void:
	await _new_game("승리")
	_check_eq(Game.state.chips_balance, 40, "new game starts with 40 chips")
	_check_eq(Game.state.time_of_day, "day", "starts in the day")
	_check(main.tutorial.visible and main.tutorial.step == 1, "tutorial step 1 (move)")
	# Playability pass 1: greetings carry no signal; one main signal (Lumi) on the first morning.
	var first_signals: Dictionary = Game.world_signals()
	_check_eq(first_signals, {"npc_lumi": "main"}, "first morning: only Lumi is marked")

	# movement and collision with real input
	var start: Vector2 = main.world.player.position
	Input.action_press("move_up")
	await _physics(24)
	Input.action_release("move_up")
	_check(main.world.player.position.distance_to(start) > 60.0, "player moves with input")
	_check_eq(main.tutorial.step, 2, "tutorial step 2 (talk)")
	main.world.player.position = Vector2(260, 380)
	await _physics(2)
	Input.action_press("move_up")
	await _physics(40)
	Input.action_release("move_up")
	_check(main.world.player.position.y >= 362.0, "building blocks movement")

	await _meet_lumi_in_plaza()
	_check_eq(main.tutorial.step, 0, "tutorial finished after the first talk")
	await _go_to("job_board", "job_board")
	await _press("interact")
	await _read_to_choices()
	_check_eq(main.dialogue._choices.map(func(c): return c.get("action", "")), ["start_job", "board", "close"], "board: today's job, news, close")
	await _choose("close")
	_check(Game.state.get_flag("tutorial_done"), "tutorial flag saved")
	await _shot("01_village_day")
	_check(main.hud._goal_label.text.contains("아르바이트") and main.hud._goal_label.text.contains("포커"), "goal lists poker as one option among others")

	# D3: declining at the card room door keeps the time as it is
	await _go_to("door", "card_room_building")
	await _press("interact")
	await _read_to_choices()
	await _choose("close")
	_check_eq(Game.state.time_of_day, "day", "declining keeps the day")
	_check_eq(main.world.location_id, "village_square", "still outside")
	await _wait_evening_at_card_room()

	await _talk("npc_moa")
	await _read_to_choices()
	Game.debug_deck_queue = [DECKS["win"]]
	await _choose("start_poker")
	_check_eq(Game.state.chips_balance, 20, "stake 20 taken: 40 -> 20")
	main.poker.ability_button.pressed.emit()
	await _frames(1)
	main.poker.player_views[4].pressed.emit(4)
	await _frames(1)
	await _shot("02_poker")
	main.poker.draw_button.pressed.emit()
	await _frames(2)
	_check_eq(main.poker.match_ref.outcome, 1, "won")
	_check_eq(Game.state.chips_balance, 60, "win returns 40: 20 -> 60")
	await _shot("02_poker_result")
	main.poker.result_leave_button.pressed.emit()
	await _frames(2)

	await _enter("door", "exit_card_room", "village_square")
	_check_eq(Game.state.time_of_day, "evening", "evening kept outside")
	_check(not main.world.npc_nodes.has("npc_lumi"), "no Lumi in the evening plaza")
	await _buy_lamp()
	_check_eq(Game.state.chips_balance, 10, "lamp 50: 60 -> 10")
	await _place_lamp("slot_window")
	await _sleep_until_morning()
	await _enter("door", "exit_home", "village_square")
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_lamp_reaction", "PATH A: Lumi reacts to the lamp")
	await _close_dialogue()
	# After the lamp: a few resident stories open, not all of them at once.
	var after: Dictionary = Game.world_signals()
	_check(Game.open_stories().size() <= 3, "at most three resident stories open after the lamp")
	_check(after.values().count("main") <= 1 and after.values().count("story") <= 2, "one main signal, two story signals at most: %s" % after)
	_check_ledger()


# --- PATH B: poker loss, then the quest ------------------------------------------

func _path_b() -> void:
	await _new_game("패배")
	# Sera's request first; Lumi has not been met yet.
	await _enter("door", "shop_building", "small_shop")
	await _talk("npc_sera")
	await _read_to_choices()
	await _choose("dialogue")
	await _read_to_choices()
	await _choose("accept_quest")
	_check_eq(QuestBook.state_of(Game.state, QUEST), "active", "quest accepted")
	# D6: the parcel is visible in the HUD, even with the goal line collapsed.
	_check(main.hud.quest_text().contains("꾸러미"), "HUD shows the parcel delivery (%s)" % main.hud.quest_text())
	main.hud.toggle_goal()
	_check(main.hud.quest_text().contains("꾸러미"), "HUD keeps the quest line when the goal is collapsed")
	main.hud.toggle_goal()
	await _close_dialogue_if_open()
	await _enter("door", "exit_shop", "village_square")
	await _wait_evening_at_card_room()

	await _talk("npc_moa")
	await _read_to_choices()
	Game.debug_deck_queue = [DECKS["lose"]]
	await _choose("start_poker")
	main.poker.stand_button.pressed.emit()
	await _frames(2)
	_check_eq(main.poker.match_ref.outcome, -1, "lost")
	_check_eq(Game.state.chips_balance, 20, "loss: 40 -> 20, no consolation")
	main.poker.result_leave_button.pressed.emit()
	await _frames(2)

	# D4: first meeting with Lumi, parcel handed over in the same conversation.
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_intro_cardroom", "first meeting comes first")
	await _read_to_choices()
	await _shot("03_intro_with_delivery")
	await _choose("complete_quest")
	_check_eq(QuestBook.state_of(Game.state, QUEST), "completed", "delivered in the same conversation")
	_check_eq(Game.state.chips_balance, 50, "quest +30: 20 -> 50")
	_check(Game.state.get_flag("intro_met_lumi"), "intro also recorded")
	await _close_dialogue()
	_check_eq(main.hud.quest_text(), "", "HUD quest line gone after delivery")

	await _enter("door", "exit_card_room", "village_square")
	await _buy_lamp()
	_check_eq(Game.state.chips_balance, 0, "lamp: 50 -> 0")
	await _place_lamp("slot_table")
	await _sleep_until_morning()
	await _enter("door", "exit_home", "village_square")
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_lamp_reaction", "PATH B: Lumi reacts to the lamp")
	await _close_dialogue()
	_check_ledger()


# --- PATH C: no poker at all -----------------------------------------------------

func _path_c() -> void:
	await _new_game("알바")
	await _meet_lumi_in_plaza()
	await _start_job()
	_check_eq(Game.job.total(), 3, "odd job asks for 3 pickups")
	var ids: Array = Game.job.remaining()
	for n in ids.size():
		await _collect_spot(ids[n])
		if n == 0:
			await _shot("04_odd_job")
	_check(Game.job == null, "job finished")
	_check_eq(Game.state.chips_balance, 50, "odd job +10: 40 -> 50")
	await _buy_lamp()
	_check_eq(Game.state.chips_balance, 0, "lamp bought without poker")
	await _place_lamp("slot_bedside")
	await _shot("05_housing")
	await _enter("door", "exit_home", "village_square")
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_lamp_reaction", "PATH C: Lumi reacts to the lamp")
	await _close_dialogue()
	_check_eq(Game.state.poker_hands_completed, 0, "PATH C: never played poker")
	_check_eq(Game.state.time_of_day, "day", "never needed the evening")
	_check_ledger()


# --- PATH D: interrupted poker ---------------------------------------------------

func _path_d1() -> void:
	await _new_game("중단")
	await _wait_evening_at_card_room()
	await _go_to("poker_table", "poker_table")
	Game.debug_deck_queue = [DECKS["win"]]
	await _press("interact")
	_check_eq(main.ui_mode, "poker", "hand in progress")
	_check_eq(_codes(main.poker.match_ref.player_hand), WIN_PLAYER, "hand dealt")
	main.poker.ability_button.pressed.emit()
	await _frames(1)
	var saved := _saved()
	var hand: Dictionary = saved.get("poker_in_progress", {})
	_check_eq(int(saved.get("chips_balance", -1)), 20, "saved balance without the stake")
	_check_eq(int(saved.get("pending_poker_stake", -1)), 20, "saved pending stake")
	_check_eq(hand.get("player_hand", []), WIN_PLAYER, "player hand saved")
	_check_eq(hand.get("opponent_hand", []), WIN_OPPONENT, "opponent hand saved")
	_check_eq((hand.get("deck", []) as Array).size(), 42, "remaining deck saved")
	_check_eq(int(hand.get("ability_uses", {}).get("ability.star_sense", 0)), 1, "ability use saved")
	# R1: a window close request mid-hand saves the hand as it is and never folds it.
	main._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	var after_close := _saved()
	_check_eq(after_close.get("poker_in_progress", {}).get("player_hand", []), WIN_PLAYER, "window close keeps the hand")
	_check_eq(int(after_close.get("pending_poker_stake", -1)), 20, "window close keeps the stake pending")
	_check_eq(int(after_close.get("poker_record", {}).get("fold", -1)), 0, "window close is not a fold")
	print("[e2e] quitting mid-hand (simulated forced quit / window close)")


func _path_d2() -> void:
	await _frames(2)
	main.title.continue_button.pressed.emit()
	for i in 240:
		if main.ui_mode == "poker":
			break
		await _frames(1)
	_check_eq(main.ui_mode, "poker", "the interrupted hand reopens on continue")
	var m: PokerMatch = main.poker.match_ref
	_check_eq(_codes(m.player_hand), WIN_PLAYER, "same player hand after restart")
	_check_eq(_codes(m.opponent_hand), WIN_OPPONENT, "same opponent hand after restart")
	_check_eq(m.deck.remaining(), 42, "same deck size")
	_check_eq(m.phase, PokerMatch.Phase.DRAW, "still before the draw")
	_check(main.poker.ability_button.disabled, "ability stays used")
	_check(main.poker._ability_label.text.contains("원페어 이상"), "ability result still shown")
	_check_eq(Game.state.chips_balance, 20, "stake not charged again")
	_check_eq(_ledger_count("poker_stake"), 1, "one stake in the ledger")
	_check_eq(_ledger_count("poker_void_refund"), 0, "no refund")
	for v in main.poker.opponent_views:
		_check(v.card == null, "opponent still hidden")
	await _shot("06_resumed_hand", 60)
	main.poker.player_views[4].pressed.emit(4)
	await _frames(1)
	main.poker.draw_button.pressed.emit()
	await _frames(2)
	_check_eq(_codes(main.poker.match_ref.player_hand), ["AS", "AH", "KD", "7C", "6H"], "draw comes from the saved deck order")
	_check_eq(main.poker.match_ref.outcome, 1, "same result as before the quit")
	_check_eq(Game.state.chips_balance, 60, "settled once: 20 -> 60")
	_check_eq(_saved().get("poker_in_progress", {"x": 1}), {}, "no hand left in the save")
	main.poker.result_leave_button.pressed.emit()
	await _frames(2)
	# Restart again: nothing to resume, nothing paid twice.
	await _press("menu")
	main.menu.title_button.pressed.emit()
	await _frames(3)
	main.title.continue_button.pressed.emit()
	await _wait_world("card_room")
	_check_eq(main.ui_mode, "world", "no poker screen after the hand was settled")
	_check_eq(Game.state.time_of_day, "evening", "evening restored after reload")
	_check(main.world.is_evening() and main.world.npc_nodes.has("npc_lumi"), "evening card room with Lumi after reload")
	_check_eq(Game.state.chips_balance, 60, "balance unchanged after another restart")
	_check_eq(_ledger_count("poker_payout_win"), 1, "one payout in the ledger")
	_check_ledger()


# --- regression -------------------------------------------------------------------

func _broke() -> void:
	await _new_game("파산")
	await _enter("door", "home_building", "player_home")
	await _go_to("rest", "home_bed")
	await _press("interact")
	_check(main.dialogue.current_line().contains("저녁"), "bed offers resting until evening")
	await _read_to_choices()
	await _choose("set_time")
	await _wait_world("player_home")
	_check_eq(Game.state.time_of_day, "evening", "rested until evening")
	await _enter("door", "exit_home", "village_square")
	await _enter("door", "card_room_building", "card_room")

	# D1: leaving mid-hand is a fold, with a warning.
	await _go_to("poker_table", "poker_table")
	Game.debug_deck_queue = [DECKS["win"]]
	await _press("interact")
	main.poker.leave_button.pressed.emit()
	await _frames(1)
	_check(main.poker._confirm_label.text.contains("돌려받지 못해요"), "leave warns about the stake")
	main.poker.confirm_leave_button.pressed.emit()
	await _frames(2)
	_check_eq(Game.state.chips_balance, 20, "fold: 40 -> 20")
	_check_eq(Game.state.poker_in_progress, {}, "folded hand not kept")

	await _go_to("poker_table", "poker_table")
	Game.debug_deck_queue = [DECKS["lose"]]
	await _press("interact")
	main.poker.stand_button.pressed.emit()
	await _frames(2)
	_check_eq(Game.state.chips_balance, 0, "lost everything")
	_check(main.poker.again_button.disabled and main.poker.again_button.text.contains("칩 부족"), "cannot play another hand at 0")
	main.poker.result_leave_button.pressed.emit()
	await _frames(2)
	await _talk("npc_moa")
	await _read_to_choices()
	await _choose("start_poker")
	_check_eq(main.ui_mode, "world", "blocked from poker below the stake")
	_check(main.hud.toast_text().contains("아르바이트"), "hint points to the odd job")

	await _enter("door", "exit_card_room", "village_square")
	await _start_job()
	var ids: Array = Game.job.remaining()
	await _collect_spot(ids[0])
	await _enter("door", "shop_building", "small_shop")
	_check(Game.job == null, "leaving the plaza cancels the job")
	_check_eq(Game.state.chips_balance, 0, "cancelled job pays nothing")
	await _enter("door", "exit_shop", "village_square")
	for run in 2:
		await _start_job()
		ids = Game.job.remaining()
		await _collect_spot(ids[0])
		for k in 5:
			await _press("interact")
		_check_eq(Game.job.collected.size(), 1, "repeated presses collect one spot only")
		_check_eq(Game.state.chips_balance, run * 10, "no pay mid-run")
		await _go_to("job_board", "job_board")
		await _press("interact")
		_check(main.dialogue.current_line().contains("1 / 3"), "board shows progress, pays nothing")
		await _press("interact")
		for n in range(1, ids.size()):
			await _collect_spot(ids[n])
		_check_eq(Game.state.chips_balance, (run + 1) * 10, "10 chips per completed run")

	await _enter("door", "card_room_building", "card_room")
	await _go_to("poker_table", "poker_table")
	Game.debug_deck_queue = [DECKS["draw"], DECKS["win"]]
	await _press("interact")
	_check_eq(main.ui_mode, "poker", "can play again with 20 chips")
	main.poker.stand_button.pressed.emit()
	await _frames(2)
	_check_eq(Game.state.chips_balance, 20, "draw returns the stake")
	main.poker.again_button.pressed.emit()
	await _frames(2)
	main.poker.stand_button.pressed.emit()
	await _frames(2)
	_check_eq(Game.state.chips_balance, 40, "win returns the pot")
	_check_ledger()


func _migrate() -> void:
	var v1 := {
		"save_version": 1, "player_name": "옛날", "chips_balance": 60,
		"chips_ledger": [{"seq": 1, "delta": 60, "reason": "poker_lose", "balance": 60}],
		"flags": {"intro_met_lumi": true, "first_poker_bonus_claimed": true, "tutorial_done": true},
		"poker_hands_completed": 1, "poker_record": {"win": 0, "draw": 0, "lose": 1},
		"owned_items": {}, "collection": [], "home_placements": [],
		"current_scene": "card_room", "player_position": [480, 560],
	}
	_write_save(JSON.stringify(v1))
	main.show_title()
	await _frames(2)
	main.title.continue_button.pressed.emit()
	await _wait_world("card_room")
	_check_eq(Game.state.chips_balance, 60, "v1 balance kept (not reset to 40)")
	_check_eq(Game.state.time_of_day, "evening", "card room save becomes evening")
	_check_eq(int(_saved().get("save_version", -1)), GameState.SAVE_VERSION, "saved as current version")

	# v2 from the previous build: stake paid, cards never saved.
	var v2 := {
		"save_version": 2, "player_name": "이전", "chips_balance": 80,
		"chips_ledger": [
			{"seq": 1, "delta": 100, "reason": "starting_chips", "balance": 100},
			{"seq": 2, "delta": -20, "reason": "poker_stake", "balance": 80},
		],
		"flags": {"intro_met_lumi": true, "tutorial_done": true}, "poker_hands_completed": 0,
		"poker_record": {"win": 0, "draw": 0, "lose": 0, "fold": 0}, "pending_poker_stake": 20,
		"time_of_day": "evening", "quests": {}, "jobs_completed": 0,
		"owned_items": {}, "collection": [], "home_placements": [],
		"current_scene": "card_room", "player_position": [480, 560],
	}
	_write_save(JSON.stringify(v2))
	main.show_title()
	await _frames(2)
	main.title.continue_button.pressed.emit()
	for i in 240:
		if main.ui_mode == "poker":
			break
		await _frames(1)
	_check_eq(main.ui_mode, "poker", "paid stake carries over to a hand")
	_check_eq(Game.state.chips_balance, 80, "no refund and no second charge")
	_check_eq(_ledger_count("poker_stake"), 1, "still one stake")
	_check(not (_saved().get("poker_in_progress", {}) as Dictionary).is_empty(), "the new hand is saved at once")
	_check_eq(int(_saved().get("save_version", -1)), GameState.SAVE_VERSION, "rewritten as current version at once")
	var first_hand := _codes(main.poker.match_ref.player_hand)
	# Loading the same save again must resume that hand, not deal another (R2).
	for attempt in 2:
		main.show_title()
		await _frames(2)
		main.title.continue_button.pressed.emit()
		for i in 240:
			if main.ui_mode == "poker":
				break
			await _frames(1)
		_check_eq(_codes(main.poker.match_ref.player_hand), first_hand, "reload %d resumes the same hand" % (attempt + 1))
		_check_eq(Game.state.chips_balance, 80, "reload %d: no charge, no refund" % (attempt + 1))
	main.poker.stand_button.pressed.emit()
	await _frames(2)
	_check_eq(Game.state.pending_poker_stake, 0, "settled")
	_check_ledger()


func _reject() -> void:
	var future := '{"save_version": 999, "player_name": "미래", "chips_balance": 999}'
	_write_save(future)
	main.show_title()
	await _frames(2)
	main.title.continue_button.pressed.emit()
	await _frames(2)
	_check_eq(main.ui_mode, "title", "newer save: stays on title")
	_check(main.title._message.text.contains("새로운 버전"), "newer save: message shown")
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
	_check_eq(Game.state.chips_balance, 40, "new game gets 40 chips")


# --- shared steps -----------------------------------------------------------------

func _meet_lumi_in_plaza() -> void:
	_check(main.world.npc_nodes.has("npc_lumi"), "day: Lumi in the plaza")
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_intro", "first meeting in the plaza")
	await _close_dialogue()


func _wait_evening_at_card_room() -> void:
	await _go_to("door", "card_room_building")
	await _press("interact")
	_check(main.dialogue.current_line().contains("저녁"), "closed-door text")
	await _read_to_choices()
	await _choose("wait_and_enter")
	await _wait_world("card_room")
	_check_eq(Game.state.time_of_day, "evening", "waited until evening")
	_check(main.world.npc_nodes.has("npc_lumi"), "evening: Lumi in the card room")


func _buy_lamp() -> void:
	await _enter("door", "shop_building", "small_shop")
	await _talk("npc_sera")
	# Sera may thank or greet first; any entry offers the shop.
	await _read_to_choices()
	await _choose("open_shop")
	main.shop.buy_buttons[LAMP].pressed.emit()
	await _frames(2)
	_check_eq(Game.state.owned_count(LAMP), 1, "lamp in storage")
	main.shop.close_button.pressed.emit()
	await _frames(2)
	await _enter("door", "exit_shop", "village_square")


func _place_lamp(slot_id: String) -> void:
	await _enter("door", "home_building", "player_home")
	await _go_to("home_edit", "home_decorate")
	await _press("interact")
	main.home_edit.item_buttons[LAMP].pressed.emit()
	await _frames(1)
	main.home_edit.slot_buttons[slot_id].pressed.emit()
	await _frames(1)
	main.home_edit.confirm_button.pressed.emit()
	await _frames(2)
	_check_eq(Game.state.placement_at(slot_id), LAMP, "lamp placed at " + slot_id)
	main.home_edit.close_button.pressed.emit()
	await _frames(2)


func _sleep_until_morning() -> void:
	await _go_to("rest", "home_bed")
	await _press("interact")
	_check(main.dialogue.current_line().contains("아침"), "bed offers sleeping until morning")
	await _read_to_choices()
	await _choose("set_time")
	await _wait_world("player_home")
	_check_eq(Game.state.time_of_day, "day", "morning")


func _close_dialogue_if_open() -> void:
	if main.ui_mode == "dialogue":
		await _close_dialogue()


func _codes(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(c.code())
	return out


func _ledger_count(reason: String) -> int:
	var n := 0
	for e in Game.state.chips_ledger:
		if e["reason"] == reason:
			n += 1
	return n


# --- VISUAL SLICE 01: first-play path with a screenshot per beat --------------------

func _slice() -> void:
	await _new_game("단비")
	main.world.player.position = Vector2(820, 600)
	await _physics(3)
	await _shot("01_square_day")
	await _talk("npc_lumi")
	await _shot("02_dialogue_lumi")
	await _close_dialogue()
	var shop: Dictionary = main.world.find_interactable("door", "shop_building")
	main.world.player.position = shop["pos"] + Vector2(0, 70)
	await _physics(3)
	await _shot("03_shop_exterior_day")
	await _enter("door", "home_building", "player_home")
	await _shot("04_home_day_before")
	await _enter("door", "exit_home", "village_square")
	var card: Dictionary = main.world.find_interactable("door", "card_room_building")
	main.world.player.position = card["pos"] + Vector2(0, 90)
	await _physics(3)
	await _shot("05_card_room_exterior_day")
	await _wait_evening_at_card_room()
	await _shot("06_card_room_evening")
	await _talk("npc_moa")
	await _read_to_choices()
	Game.debug_deck_queue = [DECKS["win"]]
	await _choose("start_poker")
	await _shot("07_poker")
	main.poker.ability_button.pressed.emit()
	await _frames(1)
	main.poker.player_views[4].pressed.emit(4)
	await _frames(1)
	await _shot("08_poker_discard")
	main.poker.draw_button.pressed.emit()
	await _frames(2)
	_check_eq(main.poker.match_ref.outcome, 1, "slice hand won")
	await _shot("09_poker_result")
	main.poker.result_leave_button.pressed.emit()
	await _frames(2)
	await _enter("door", "exit_card_room", "village_square")
	main.world.player.position = Vector2(820, 600)
	await _physics(3)
	await _shot("10_square_evening")
	main.world.player.position = card["pos"] + Vector2(0, 90)
	await _physics(3)
	await _shot("11_card_room_exterior_evening")
	await _enter("door", "shop_building", "small_shop")
	await _talk("npc_sera")
	await _read_to_choices()
	await _choose("open_shop")
	await _shot("12_shop")
	main.shop.buy_buttons[LAMP].pressed.emit()
	await _frames(2)
	main.shop.close_button.pressed.emit()
	await _frames(2)
	await _enter("door", "exit_shop", "village_square")
	await _enter("door", "home_building", "player_home")
	await _shot("13_home_evening_before")
	await _go_to("home_edit", "home_decorate")
	await _press("interact")
	main.home_edit.item_buttons[LAMP].pressed.emit()
	await _frames(1)
	main.home_edit.slot_buttons["slot_window"].pressed.emit()
	await _frames(1)
	await _shot("14_home_edit")
	main.home_edit.confirm_button.pressed.emit()
	await _frames(2)
	main.home_edit.close_button.pressed.emit()
	await _frames(2)
	_check_eq(Game.state.placement_at("slot_window"), LAMP, "slice lamp placed")
	await _shot("15_home_evening_lamp")
	await _sleep_until_morning()
	await _shot("16_home_morning_lamp")
	await _enter("door", "exit_home", "village_square")
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_lamp_reaction", "slice: Lumi reacts to the lamp")
	await _press("interact")
	await _shot("17_lumi_reaction")
	await _close_dialogue()


# --- helpers ---------------------------------------------------------------------

func _new_game(player_name: String) -> void:
	SaveSystem.delete(Game.save_path)
	main.show_title()
	await _frames(3)
	main.title.new_game_button.pressed.emit()
	await _frames(1)
	main.title.name_edit.text = player_name
	main.title.start_button.pressed.emit()
	await _wait_world("village_square")


func _start_job() -> void:
	await _go_to("job_board", "job_board")
	await _press("interact")
	await _read_to_choices()
	await _choose("start_job")
	_check(Game.job != null, "job started")
	await _physics(2)


func _collect_spot(spot_id: String) -> void:
	await _go_to("job_pickup", spot_id)
	await _press("interact")


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
		"sign", "job_board":
			return pos + Vector2(0, 30)
		"job_pickup":
			return pos
	return pos + Vector2(0, 8)


## Places the player next to a target (walking is covered by the movement checks) and
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
	# Wait for any transition to start and finish.
	await _frames(2)
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
