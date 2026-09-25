extends Node
## End-to-end driver for the first-play loop (spec v0.2 + Design Correction 02 + Economy v0.2.1).
## Runs inside the real game (Main scene + Game autoload). Movement and interaction use real
## input actions; buttons and cards are triggered through the same signals a mouse click emits.
## Exits with code 0 when every check passed, 1 otherwise.
##   godot --headless --path game -- --e2e=<scenario> --save-path=user://e2e.json [--shots=<abs dir>]
## Scenarios:
##   win, draw, lose     full loop per poker outcome (time of day, quest, stake, lamp, rest)
##   broke               lose everything -> blocked from poker -> odd jobs -> play again
##   resume_a/b/c        three processes: quit mid-hand, continue (stake refund), continue again
##   migrate             a version-1 save keeps its chips
##   reject              unreadable saves

const DECKS := {
	# Deal order is player, opponent, player, ... then draws. See tests/unit/test_poker_match.gd.
	"win": ["AS", "QS", "AH", "QH", "KD", "9D", "7C", "5C", "2S", "3H", "6H", "4D", "8S", "JC"],
	"draw": ["KS", "KD", "KH", "KC", "9C", "9H", "7D", "7S", "4S", "4H", "9D", "7H", "4C"],
	"lose": ["2C", "AH", "5D", "AC", "8H", "6S", "JS", "9C", "3D", "TD", "4S", "7C", "KH"],
}
const NET := {"win": 20, "draw": 0, "lose": -20}
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
		"win", "draw", "lose":
			await _first_play(scenario)
		"broke":
			await _broke()
		"resume_a":
			await _resume_a()
		"resume_b":
			await _resume_b()
		"resume_c":
			await _resume_c()
		"migrate":
			await _migrate()
		"reject":
			await _reject()
		_:
			_check(false, "unknown scenario " + scenario)
	_finish()


# --- scenarios -------------------------------------------------------------------

func _first_play(outcome: String) -> void:
	await _new_game("테스터")
	_check_eq(Game.state.chips_balance, 100, "new game starts with 100 chips")
	_check_eq(Game.state.time_of_day, "day", "new game starts in the day")
	_check(main.tutorial.visible and main.tutorial.step == 1, "tutorial step 1 (move)")

	# movement and collision with real input
	var start: Vector2 = main.world.player.position
	Input.action_press("move_up")
	await _physics(24)
	Input.action_release("move_up")
	_check(main.world.player.position.distance_to(start) > 60.0, "player moves with input")
	_check_eq(main.tutorial.step, 2, "tutorial advances to step 2 (talk)")
	main.world.player.position = Vector2(260, 380)
	await _physics(2)
	Input.action_press("move_up")
	await _physics(40)
	Input.action_release("move_up")
	_check(main.world.player.position.y >= 362.0, "building blocks movement")

	# Lumi stands in the plaza by day
	_check(main.world.npc_nodes.has("npc_lumi"), "day: Lumi in the plaza")
	await _go_to("npc", "npc_lumi")
	await _shot("01_village_day")
	await _press("interact")
	_check_eq(main.last_entry_id, "lumi_intro", "first meeting")
	_check(main.dialogue.current_line().contains("테스터"), "Lumi uses the player's name")
	await _read_to_choices()
	await _choose("close")
	_check(Game.state.get_flag("intro_met_lumi"), "intro flag")

	# Sera's one-time request
	await _enter("door", "shop_building", "small_shop")
	await _talk("npc_sera")
	_check_eq(main.last_entry_id, "sera_first", "Sera greets")
	await _read_to_choices()
	await _choose("dialogue")
	_check_eq(main.last_entry_id, "sera_quest_offer", "Sera offers the delivery")
	await _read_to_choices()
	await _choose("accept_quest")
	_check_eq(QuestBook.state_of(Game.state, QUEST), "active", "quest accepted")
	_check(main.hud._goal_label.text.contains("꾸러미"), "goal shows the delivery")
	_check(_saved().get("quests", {}).get(QUEST, "") == "active", "quest state saved")
	await _talk("npc_sera")
	_check_eq(main.last_entry_id, "sera_quest_active", "Sera reminds while active")
	await _close_dialogue()
	await _enter("door", "exit_shop", "village_square")

	# The card room is closed by day: wait for the evening at its door
	await _go_to("door", "card_room_building")
	await _press("interact")
	_check_eq(main.ui_mode, "dialogue", "closed door explains the gathering is in the evening")
	_check(main.dialogue.current_line().contains("저녁"), "closed-door text")
	await _read_to_choices()
	await _choose("wait_and_enter")
	await _wait_world("card_room")
	_check_eq(Game.state.time_of_day, "evening", "waiting made it evening")
	_check(main.world.is_evening(), "evening lighting")
	_check(main.world.npc_nodes.has("npc_lumi"), "evening: Lumi in the card room")
	await _shot("02_card_room_evening", 170)

	# Deliver the parcel to Lumi (evening -> card room)
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_quest_delivery", "Lumi recognises the parcel")
	await _read_to_choices()
	await _choose("complete_quest")
	_check_eq(QuestBook.state_of(Game.state, QUEST), "completed", "quest completed")
	_check_eq(Game.state.chips_balance, 130, "quest pays 30 once")
	_check_eq(main.last_entry_id, "lumi_quest_thanks", "Lumi thanks")
	await _read_to_choices()
	await _choose("close")
	await _talk("npc_lumi")
	_check(main.last_entry_id != "lumi_quest_delivery", "no second delivery")
	_check_eq(Game.state.chips_balance, 130, "no second quest reward")
	await _close_dialogue()

	# Poker with the fixed stake
	await _talk("npc_moa")
	_check_eq(main.last_entry_id, "moa_first", "Moa explains the stake")
	_check(main.dialogue.current_line() != "", "Moa speaks")
	await _read_to_choices()
	Game.debug_deck_queue = [DECKS[outcome], DECKS["lose"]]
	await _choose("start_poker")
	_check_eq(main.ui_mode, "poker", "poker starts")
	_check_eq(Game.state.chips_balance, 110, "stake 20 taken when the hand starts")
	_check_eq(Game.state.pending_poker_stake, 20, "stake pending")
	_check_eq(int(_saved().get("pending_poker_stake", -1)), 20, "pending stake saved")
	var poker = main.poker
	for v in poker.opponent_views:
		_check(v.card == null, "opponent hidden before showdown")
	poker.ability_button.pressed.emit()
	await _frames(1)
	_check(poker._ability_label.text.contains("원페어 이상"), "Star Sense answers")
	if outcome == "win":
		poker.player_views[4].pressed.emit(4)
		await _frames(1)
		await _shot("03_poker")
		poker.draw_button.pressed.emit()
	else:
		await _shot("03_poker")
		poker.stand_button.pressed.emit()
	await _frames(2)
	_check_eq(poker.match_ref.outcome, {"win": 1, "draw": 0, "lose": -1}[outcome], "outcome " + outcome)
	_check_eq(Game.state.chips_balance, 130 + NET[outcome], "net %d after the hand" % NET[outcome])
	_check_eq(Game.state.pending_poker_stake, 0, "nothing pending after showdown")
	_check_ledger()
	_check_eq(int(_saved().get("chips_balance", -1)), 130 + NET[outcome], "settlement saved")
	await _shot("03_poker_result")
	poker.again_button.pressed.emit()
	await _frames(2)
	poker.stand_button.pressed.emit()
	await _frames(2)
	var after_poker: int = 130 + NET[outcome] - 20
	_check_eq(Game.state.chips_balance, after_poker, "second hand lost: -20, no consolation")
	poker.result_leave_button.pressed.emit()
	await _frames(2)

	# Evening persists outside; Lumi is not duplicated in the plaza
	await _enter("door", "exit_card_room", "village_square")
	_check_eq(Game.state.time_of_day, "evening", "still evening after leaving the card room")
	_check(main.world.is_evening(), "village is lit for the evening")
	_check(not main.world.npc_nodes.has("npc_lumi"), "evening: Lumi is not in the plaza")
	await _shot("04_village_evening")

	# Buy and place the lamp
	await _enter("door", "shop_building", "small_shop")
	_check(main.world.is_evening(), "evening inside the shop too")
	await _talk("npc_sera")
	_check_eq(main.last_entry_id, "sera_quest_done", "Sera thanks for the delivery")
	await _read_to_choices()
	await _choose("open_shop")
	main.shop.buy_buttons[LAMP].pressed.emit()
	await _frames(2)
	_check_eq(Game.state.chips_balance, after_poker - 50, "lamp costs 50")
	main.shop.close_button.pressed.emit()
	await _frames(2)
	await _enter("door", "exit_shop", "village_square")
	await _enter("door", "home_building", "player_home")
	await _go_to("home_edit", "home_decorate")
	await _press("interact")
	var edit = main.home_edit
	edit.item_buttons[LAMP].pressed.emit()
	await _frames(1)
	edit.slot_buttons["slot_window"].pressed.emit()
	await _frames(1)
	edit.confirm_button.pressed.emit()
	await _frames(2)
	_check_eq(Game.state.placement_at("slot_window"), LAMP, "lamp placed")
	await _shot("05_housing")
	edit.close_button.pressed.emit()
	await _frames(2)

	# Save and reload keeps the evening
	await _press("menu")
	main.menu.title_button.pressed.emit()
	await _frames(3)
	main.title.continue_button.pressed.emit()
	await _wait_world("player_home")
	_check_eq(Game.state.time_of_day, "evening", "evening restored after reload")
	_check(main.world.is_evening(), "evening lighting after reload")
	_check_eq(Game.state.chips_balance, after_poker - 50, "chips restored")

	# Rest at home: back to day, Lumi back in the plaza
	await _go_to("rest", "home_bed")
	await _press("interact")
	_check(main.dialogue.current_line().contains("아침"), "bed offers sleeping until morning")
	await _read_to_choices()
	await _choose("set_time")
	await _wait_world("player_home")
	_check_eq(Game.state.time_of_day, "day", "resting makes it day")
	_check(not main.world.is_evening(), "day lighting")
	await _enter("door", "exit_home", "village_square")
	_check(main.world.npc_nodes.has("npc_lumi"), "day: Lumi back in the plaza")
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_lamp_reaction", "Lumi reacts to the lamp")
	await _close_dialogue()
	_check_eq(Game.state.chips_balance, after_poker - 50, "final balance")
	_check_ledger()


## Lose everything, get blocked, recover through odd jobs, and play again.
func _broke() -> void:
	await _new_game("파산")
	# The bed also turns day into evening.
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
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_intro_cardroom", "met Lumi first at the card room")
	await _close_dialogue()

	# A hand left early is folded: the stake is lost.
	await _go_to("poker_table", "poker_table")
	Game.debug_deck_queue = [DECKS["win"]]
	await _press("interact")
	_check_eq(Game.state.chips_balance, 80, "stake taken")
	main.poker.leave_button.pressed.emit()
	await _frames(1)
	_check(main.poker._confirm_label.text.contains("돌려받지 못해요"), "leave warns about the stake")
	main.poker.confirm_leave_button.pressed.emit()
	await _frames(2)
	_check_eq(main.ui_mode, "world", "left the table")
	_check_eq(Game.state.chips_balance, 80, "fold: stake not returned")
	_check_eq(Game.state.pending_poker_stake, 0, "fold resolved")
	_check_eq(Game.state.poker_record["fold"], 1, "fold recorded")

	# Four losses: 80 -> 0.
	await _go_to("poker_table", "poker_table")
	Game.debug_deck_queue = [DECKS["lose"], DECKS["lose"], DECKS["lose"], DECKS["lose"]]
	await _press("interact")
	for i in 4:
		main.poker.stand_button.pressed.emit()
		await _frames(2)
		if i < 3:
			main.poker.again_button.pressed.emit()
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
	_check(main.hud._goal_label.text.contains("아르바이트"), "goal points to the odd job")
	_check_eq(Game.state.chips_balance, 0, "still 0")

	# A cancelled run pays nothing.
	await _enter("door", "exit_card_room", "village_square")
	await _start_job()
	var ids: Array = Game.job.remaining()
	await _collect_spot(ids[0])
	await _collect_spot(ids[1])
	await _enter("door", "shop_building", "small_shop")
	_check(Game.job == null, "leaving the plaza cancels the job")
	_check_eq(Game.state.chips_balance, 0, "cancelled job pays nothing")
	await _enter("door", "exit_shop", "village_square")

	# Two full runs: 0 -> 20.
	for run in 2:
		await _start_job()
		ids = Game.job.remaining()
		# Pressing interact again and again on one spot does not pay.
		await _collect_spot(ids[0])
		for k in 5:
			await _press("interact")
		_check_eq(Game.job.collected.size(), 1, "repeated presses collect one spot only")
		_check_eq(Game.state.chips_balance, run * 10, "no pay mid-run")
		await _go_to("job_board", "job_board")
		await _press("interact")
		_check(main.dialogue.current_line().contains("1 / 5"), "board shows progress, pays nothing")
		await _press("interact")
		if run == 0:
			await _shot("06_odd_job")
		for n in range(1, ids.size()):
			await _collect_spot(ids[n])
		_check(Game.job == null, "run finished")
		_check_eq(Game.state.chips_balance, (run + 1) * 10, "10 chips per completed run")
	_check_eq(Game.state.jobs_completed, 2, "two runs counted")
	_check_ledger()

	# Back to the table.
	await _enter("door", "card_room_building", "card_room")
	await _go_to("poker_table", "poker_table")
	Game.debug_deck_queue = [DECKS["win"]]
	await _press("interact")
	_check_eq(main.ui_mode, "poker", "can play again with 20 chips")
	_check_eq(Game.state.chips_balance, 0, "stake taken")
	main.poker.stand_button.pressed.emit()
	await _frames(2)
	_check_eq(Game.state.chips_balance, 40, "win returns the 40-chip pot")


func _resume_a() -> void:
	await _new_game("재개")
	await _go_to("door", "card_room_building")
	await _press("interact")
	await _read_to_choices()
	await _choose("wait_and_enter")
	await _wait_world("card_room")
	await _go_to("poker_table", "poker_table")
	await _press("interact")
	_check_eq(main.ui_mode, "poker", "hand in progress")
	var saved := _saved()
	_check_eq(int(saved.get("chips_balance", -1)), 80, "saved balance without the stake")
	_check_eq(int(saved.get("pending_poker_stake", -1)), 20, "saved pending stake")
	print("[e2e] quitting mid-hand without saving (simulated crash)")


func _resume_b() -> void:
	await _frames(2)
	main.title.continue_button.pressed.emit()
	await _wait_world("card_room")
	_check_eq(Game.state.chips_balance, 100, "interrupted hand refunded once")
	_check_eq(Game.state.pending_poker_stake, 0, "nothing pending")
	_check_eq(Game.state.chips_ledger.back()["reason"], "poker_void_refund", "refund in the ledger")
	_check(main.hud.toast_text().contains("돌려받았어요"), "refund explained")
	_check_eq(Game.state.time_of_day, "evening", "evening restored")
	_check(main.world.npc_nodes.has("npc_lumi"), "Lumi in the card room after reload")
	await _go_to("poker_table", "poker_table")
	Game.debug_deck_queue = [DECKS["win"]]
	await _press("interact")
	main.poker.stand_button.pressed.emit()
	await _frames(2)
	_check_eq(Game.state.chips_balance, 120, "win after resume")
	main.poker.result_leave_button.pressed.emit()
	await _frames(2)
	await _enter("door", "exit_card_room", "village_square")
	await _enter("door", "shop_building", "small_shop")
	await _talk("npc_sera")
	await _read_to_choices()
	await _choose("dialogue")
	await _read_to_choices()
	await _choose("accept_quest")
	await _press("menu")
	main.menu.save_button.pressed.emit()
	await _frames(1)
	_check(main.menu._status.text.contains("저장했어요"), "saved")


func _resume_c() -> void:
	await _frames(2)
	main.title.continue_button.pressed.emit()
	await _wait_world("small_shop")
	_check_eq(QuestBook.state_of(Game.state, QUEST), "active", "quest restored as active")
	_check_eq(Game.state.chips_balance, 120, "balance restored")
	_check_eq(Game.state.chips_ledger.back()["reason"], "poker_payout_win", "no refund repeated")
	await _enter("door", "exit_shop", "village_square")
	_check(not main.world.npc_nodes.has("npc_lumi"), "evening: no Lumi in the plaza")
	await _enter("door", "card_room_building", "card_room")
	# First meeting comes first; the parcel is handed over when talking again.
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_intro_cardroom", "Lumi introduces herself first")
	await _close_dialogue()
	await _talk("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_quest_delivery", "deliver after restart")
	await _read_to_choices()
	await _choose("complete_quest")
	_check_eq(Game.state.chips_balance, 150, "quest pays 30")
	await _read_to_choices()
	await _choose("close")
	# reload inside the same process: no second reward
	await _press("menu")
	main.menu.title_button.pressed.emit()
	await _frames(3)
	main.title.continue_button.pressed.emit()
	await _wait_world("card_room")
	await _talk("npc_lumi")
	_check(main.last_entry_id != "lumi_quest_delivery", "no delivery after reload")
	_check_eq(Game.state.chips_balance, 150, "no duplicate quest reward after reload")
	var quest_entries := 0
	for e in Game.state.chips_ledger:
		if str(e["reason"]).begins_with("quest:"):
			quest_entries += 1
	_check_eq(quest_entries, 1, "one quest payment in the ledger")


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
	_check_eq(Game.state.chips_balance, 60, "v1 balance kept, not reset to 100")
	_check_eq(Game.state.time_of_day, "evening", "card room save becomes evening")
	_check(main.world.npc_nodes.has("npc_lumi"), "Lumi present")
	_check_eq(int(_saved().get("save_version", -1)), 2, "saved as v2")


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
	_check_eq(Game.state.chips_balance, 100, "new game gets 100 chips")


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
