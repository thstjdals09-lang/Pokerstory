extends "res://tests/e2e/first_play_e2e.gd"
## End-to-end driver for the content v0.3 cases (06_integration/05_ACCEPTANCE_AND_QA_MATRIX).
## Same rules as first_play_e2e.gd: the real Main scene, real input for movement and interaction,
## buttons and cards through the signals a click emits. Travel between places goes through the
## actual doors, gates and exits (route found over the location data, then walked hop by hop).
##   godot --headless --path game -- --e2e=cc04 --save-path=user://e2e_cc04.json
## Scenarios:
##   cc04   every district and functional place: enter, move, interact, return; locked doors;
##          time kept while travelling; save and continue inside a district
##   story / cc01  new game, no poker: odd job -> lamp -> Lumi -> act 1 -> act 2 -> first house
##          expansion paid with odd jobs -> act 3 festival -> postgame
##   cc05   meet all 16 residents (greetings, one place each at day and evening), then offer,
##          accept and finish all 32 personal episodes at their real targets
##   cc06   rivalry scene vs friendship, romance accepted -> dates -> together -> ended,
##          romance declined, resident pair bonded by an episode and its reaction
##   cc07   8 town projects funded at the hall board with their world changes, house stages 1-3,
##          one item placed in each room, occupied slots refused, placements kept after continue
##   life   the 4 odd jobs (including a cancelled run) and all 16 requests through play
##   cc08   poker: free practice, social mix with 7 residents, friendly challenge with 3, card-room
##          and house home games, all 8 abilities, ability + quit -> same hand, fold, tournament
##          with a lost round, a resumed round and a one-time reward
##   cc09   quit and continue in every place (day and evening), in every poker mode, during an
##          odd job, right after funding a project and with an active request
##   cc10   a v3 save mid-hand resumes and enters the new story; a damaged v3 save is refused
##   cc11   every one of the 65 items obtained in play (scenes, projects, tournament, shops,
##          trades), each placeable item shown in the house and each wearable worn
##   savefail  v0.3.1: a failed save rolls back jobs, purchases, placement, requests, projects, house,
##          trades, equipment, a one-time event, poker stake / fold / settlement and the tournament
##          reward; each done again applies once, and the file on disk always matches the game
##   economy  v0.3.1 long economy audit with real earnings only (no test_grant), no-poker and mixed
##          runs from a new save to the lamp, house stage 3 and all 8 projects; writes
##          user://economy_audit.json
##   react  cross-system reactions 2-10 caused in play (1 and 11-12 are in cc01)
##   cc12   declined scene offered again, act 2 scene missed at night then found by day, festival
##          skipped and slept through then held, festival repeated without a second memento


func run(scenario: String) -> void:
	_scenario = scenario
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots_dir = arg.get_slice("=", 1)
	print("[e2e] scenario=%s save=%s" % [scenario, Game.save_path])
	await _frames(5)
	match scenario:
		"cc04":
			await _cc04()
		"story", "cc01":
			await _story()
		"cc05":
			await _cc05()
		"cc06":
			await _cc06()
		"cc07":
			await _cc07()
		"life":
			await _life()
		"cc08":
			await _cc08()
		"cc09":
			await _cc09()
		"cc10":
			await _cc10()
		"cc11":
			await _cc11()
		"cc12":
			await _cc12()
		"react":
			await _react()
		"savefail":
			await _savefail()
		"economy":
			await _economy()
		_:
			_check(false, "unknown scenario " + scenario)
	_finish()


# --- cc04: districts and places -------------------------------------------------------

func _cc04() -> void:
	await _new_game("지도")
	Game.state.set_flag("tutorial_done")
	main.tutorial.visible = false
	var districts := {}
	# Locked doors say why and do not move the player.
	await _travel("market")
	await _go_to("door", "workshop_building")
	await _press("interact")
	_check_eq(main.ui_mode, "dialogue", "locked workshop explains itself")
	_check(main.dialogue._lines[0].contains("게시판 수선"), "locked text names the project")
	await _close_any()
	_check_eq(main.world.location_id, "market", "still in the market")
	# Open everything the normal way would open later (projects, first request, house stages).
	Game.state.quests["quest.sera_delivery"] = QuestBook.COMPLETED
	for pid in ["board_restoration", "guest_cottage"]:
		Game.state.projects[pid] = "complete"
	Game.state.home_stage = 3
	Game.state.set_flag("story.act3_started")
	Game.state.set_flag("story.act2_complete")
	var order: Array = Game.data.locations.keys()
	for loc_id in order:
		if loc_id == "card_room":
			continue  # evening only; covered below
		await _travel(loc_id)
		_check_eq(main.world.location_id, loc_id, "arrived at " + loc_id)
		await _walk_check(loc_id)
		await _shot("loc_" + loc_id)
	for pid in Game.data.places:
		var pl: Dictionary = Game.data.places[pid]
		districts[pl["district"]] = true
		await _visit_place(pid, pl)
	_check_eq(districts.size(), 5, "five districts visited")
	# Time of day is kept while travelling; the card room opens in the evening.
	await _rest_until("day")
	await _rest_until("evening")
	await _travel("grove")
	_check_eq(Game.state.time_of_day, "evening", "evening kept after crossing districts")
	await _travel("card_room")
	_check_eq(main.world.location_id, "card_room", "card room open in the evening")
	await _travel("waterfront")
	_check_eq(Game.state.time_of_day, "evening", "still evening at the waterfront")
	# Save inside a district and continue there.
	var pos: Vector2 = main.world.player.position
	main.return_to_title()
	await _frames(3)
	main.title.continue_button.pressed.emit()
	await _wait_world("waterfront")
	_check(main.world.player.position.distance_to(pos) < 4.0, "continue returns to the same spot")
	_check_eq(Game.state.time_of_day, "evening", "continue keeps the time")
	_check_ledger()


## Each functional place: travel to its scene, find its entrance and use it.
func _visit_place(pid: String, pl: Dictionary) -> void:
	await _travel(str(pl["scene"]) if pl["entrance"] == "spawn" or _entrance_in(pl["scene"], pl["entrance"]) else _parent_of(pl["scene"]))
	var ent := str(pl["entrance"])
	if ent == "spawn":
		_check_eq(main.world.location_id, pl["scene"], "place %s reached" % pid)
		return
	var target: Dictionary = {}
	for it in main.world.interactables:
		if it["id"] == ent:
			target = it
	_check(not target.is_empty(), "place %s entrance %s found" % [pid, ent])
	if target.is_empty():
		return
	if target["kind"] == "door":
		await _through_door(ent, str(target["target"]))
		_check_eq(main.world.location_id, pl["scene"], "place %s entered" % pid)
		return
	if target["kind"] == "poker_table":
		# Poker tables open the table setup in Stage 5; here only the approach is checked.
		await _go_to("poker_table", ent)
		return
	await _go_to(str(target["kind"]), ent)
	await _press("interact")
	_check(main.ui_mode != "world", "place %s responds (%s)" % [pid, main.ui_mode])
	await _close_any()


func _entrance_in(scene: String, ent: String) -> bool:
	var loc: Dictionary = Game.data.locations[scene]
	for group in ["interactables", "buildings", "gates", "exits"]:
		for it in loc.get(group, []):
			if it.get("id", "") == ent:
				return true
	return false


func _parent_of(scene: String) -> String:
	for loc_id in Game.data.locations:
		for b in Game.data.locations[loc_id].get("buildings", []):
			if b.get("target", "") == scene:
				return loc_id
	return scene


## Walks a little toward the middle of the place and checks the player really moved.
func _walk_check(loc_id: String) -> void:
	var p: Vector2 = main.world.player.position
	var size := Geo.vec(Game.data.locations[loc_id]["size"])
	var dir := (size / 2.0 - p)
	var action := ("move_right" if dir.x > 0 else "move_left") if absf(dir.x) > absf(dir.y) else ("move_down" if dir.y > 0 else "move_up")
	Input.action_press(action)
	await _physics(12)
	Input.action_release(action)
	await _physics(2)
	_check(main.world.player.position.distance_to(p) > 20.0, "can walk after arriving at " + loc_id)


# --- story (cc01 core) ------------------------------------------------------------------

func _story() -> void:
	await _new_game("이야기")
	Game.state.set_flag("tutorial_done")
	main.tutorial.visible = false
	# Prologue without poker: greet Lumi, earn chips with the plaza job, buy and place the lamp.
	await _talk_npc("npc_lumi")
	await _close_any()
	await _start_job()
	for spot_id in Game.job.remaining():
		await _collect_spot(spot_id)
	_check_eq(Game.state.chips_balance, 50, "40 + job 10 = 50")
	await _travel("small_shop")
	await _talk_npc("npc_sera")
	await _read_to_choices()
	await _choose("open_shop")
	main.shop.buy_buttons["furniture.lamp_small"].pressed.emit()
	await _frames(2)
	main.shop.close()
	await _frames(2)
	await _travel("player_home")
	await _go_to("home_edit", "home_decorate")
	await _press("interact")
	main.home_edit.item_buttons["furniture.lamp_small"].pressed.emit()
	await _frames(1)
	main.home_edit.slot_buttons["slot_window"].pressed.emit()
	await _frames(1)
	main.home_edit.confirm_button.pressed.emit()
	await _frames(1)
	main.home_edit.close_button.pressed.emit()
	await _frames(2)
	_check(Game.state.is_item_placed("furniture.lamp_small"), "lamp placed")
	await _talk_npc("npc_lumi")
	_check_eq(main.last_entry_id, "lumi_lamp_reaction", "Lumi reacts to the lamp")
	await _close_any()
	_check(Game.state.get_flag("story.prologue_complete"), "prologue complete")
	_check(main.hud._goal_label.text.contains("모아"), "goal points to Moa")

	# Act 1: the missing invitation.
	await _talk_npc("npc_moa")
	await _close_any()
	await _talk_npc("npc_moa")
	_check_eq(main.last_entry_id, "scn.missing_invitation", "Moa tells about the invitation")
	await _choose_text("찾아볼게요")
	_check(Game.state.get_flag("story.act1_started"), "act 1 started")
	await _use("postbox_stamp_spot", "residential")
	_check(Game.state.get_flag("story.clue_postbox"), "postbox clue")
	await _close_any()
	await _use("grove_sign_west", "grove")
	await _close_any()
	await _use("grove_sign_east", "grove")
	await _close_any()
	_check(Game.state.get_flag("story.clue_grove"), "grove clue")
	await _use("card_room_board", "village_square")
	await _choose_text("포커를 몰라도")
	await _choose_text("좋아요")
	_check(Game.state.get_flag("story.act1_complete"), "act 1 complete")
	await _shot("story_act1")

	# Act 2: two tables, the morning after.
	_check(main.hud._goal_label.text.contains("하루"), "the goal says a day will pass (%s)" % main.hud._goal_label.text)
	await _next_day()
	await _talk_npc("npc_lumi")
	_check_eq(main.last_entry_id, "scn.lumi_view", "Lumi's view")
	await _close_any()
	await _talk_npc("npc_kyle")
	await _close_any()
	await _talk_npc("npc_kyle")
	_check_eq(main.last_entry_id, "scn.kyle_view", "Kyle's view")
	await _close_any()
	await _talk_npc("npc_kyle")
	_check_eq(main.last_entry_id, "scn.rules_prep_offer", "Kyle asks for help with the rules board")
	await _choose_text("규칙판")
	for i in 3:
		await _use("rules_board", "grove")
		await _close_any()
	await _talk_npc("npc_kyle")
	_check_eq(main.last_entry_id, "scn.rules_prep_done", "rules board done")
	await _close_any()
	_check(Game.state.get_flag("story.act2_prep_done"), "preparation done")
	await _talk_npc("npc_lumi")
	_check_eq(main.world.location_id, "waterfront", "Lumi waits at the waterfront")
	_check_eq(main.last_entry_id, "scn.two_tables_argument_lumi", "the argument scene")
	await _choose_text("둘 다")
	await _choose_text("좋아요")
	_check(Game.state.get_flag("story.act2_complete"), "act 2 complete")
	await _shot("story_act2")

	# The first house expansion, paid with odd jobs only (after Lumi's first episode opens it).
	await _accept_offer("npc_lumi", "npc_lumi.bond_01")
	await _finish_task("npc_lumi.bond_01", 0)
	var runs := 0
	while Game.state.chips_balance < 90 and runs < 12:
		await _travel("village_square")
		await _start_job()
		for spot in Game.job.remaining():
			await _collect_spot(spot)
		runs += 1
	print("[e2e] odd jobs before the first expansion: %d" % runs)
	await _upgrade_home(1)
	_check_eq(Game.state.home_stage, 1, "house expanded without poker")

	# Act 3: the festival, prepared without poker (the morning after act 2).
	await _next_day()
	await _talk_npc("npc_juno")
	await _close_any()
	await _talk_npc("npc_juno")
	await _choose_text("장식")
	await _talk_npc("npc_moa")
	await _choose_text("관전")
	_check_eq(Game.state.contributions.size(), 2, "two contributions")
	await _talk_npc("npc_nora")
	await _close_any()
	await _accept_offer("npc_nora", "quest.festival_letters")
	await _talk_npc("npc_juno")
	await _read_to_choices()
	await _choose("complete_quest")
	await _close_any()
	_check_eq(Game.state.quests.get("quest.festival_letters", ""), QuestBook.COMPLETED, "festival letters delivered")
	_check_eq(Game.state.contributions.size(), 3, "three contributions")
	await _use("hall_meeting", "community_hall")
	await _choose_text("하트")
	_check(Game.state.get_flag("story.festival_ready"), "festival ready")
	await _use("festival_booth", "village_square")
	_check_eq(main.last_entry_id, "scn.fourleaf_wait", "the booth waits for the evening")
	await _read_to_choices()
	await _choose("set_time")
	await _wait_world("village_square")
	await _use("festival_booth", "village_square")
	_check(main.last_entry_id.begins_with("scn.fourleaf_evening"), "the festival starts")
	await _choose_text("관전")
	await _choose_text("계속 둘러보기")
	await _choose_text("좋은 저녁")
	_check(Game.state.get_flag("story.act3_complete"), "act 3 complete")
	await _shot("story_festival")
	# Postgame: sleep, then Lumi in the morning.
	await _rest_until("day")
	await _talk_npc("npc_lumi")
	_check_eq(main.last_entry_id, "scn.postgame_lumi", "postgame morning scene")
	await _close_any()
	_check(Game.state.get_flag("story.postgame"), "postgame")
	# Reactions 11-12: the first festival is talked about; Moa thanks a player who never played.
	await _talk_until("npc_moa", "moa_no_poker_festival")
	await _close_any()
	for npc in ["npc_juno", "npc_kyle", "npc_lumi", "npc_miri"]:
		await _talk_until(npc, npc.trim_prefix("npc_") + "_festival", 5)
		await _close_any()
	_check_eq(Game.state.poker_hands_completed, 0, "the whole story without a single poker hand")
	_check_ledger()


# --- cc05: residents and episodes -----------------------------------------------------------

const GREETINGS := {"npc_lumi": "lumi_intro", "npc_moa": "moa_first", "npc_sera": "sera_first"}


func _setup_open_town() -> void:
	# Scene gates only (covered by cc04/story): lamp placed, act 1 reached, workshop, cottage and
	# tailor open. Nothing here meets residents or starts episodes.
	var s: GameState = Game.state
	s.set_flag("tutorial_done")
	main.tutorial.visible = false
	s.grant_item("furniture.lamp_small")
	s.place_item("slot_window", "furniture.lamp_small")
	s.quests["quest.sera_delivery"] = QuestBook.COMPLETED
	for f in ["sera_quest_thanked", "story.prologue_complete", "story.act1_started", "story.clue_postbox", "story.clue_grove", "story.act1_complete"]:
		s.set_flag(f)
	for pid in ["board_restoration", "guest_cottage"]:
		s.projects[pid] = "complete"


func _cc05() -> void:
	await _new_game("이웃")
	_setup_open_town()
	# Each resident stands in exactly one place, by day and by evening.
	for time in ["day", "evening"]:
		Game.state.time_of_day = time
		var seen := {}
		for loc_id in Game.data.locations:
			if (loc_id == "card_room" and time == "day") or not _reachable(loc_id):
				continue
			await _travel(loc_id)
			for npc in main.world.npc_nodes:
				_check(not seen.has(npc), "%s appears once in the %s (%s)" % [npc, time, loc_id])
				seen[npc] = loc_id
		_check_eq(seen.size(), 16, "all 16 residents somewhere in the %s" % time)
	await _rest_until("day")
	# First greetings.
	for npc in Game.data.npc_order:
		await _talk_npc(npc)
		var want: String = GREETINGS.get(npc, npc.trim_prefix("npc_") + "_greet")
		_check_eq(main.last_entry_id, want, npc + " first greeting")
		await _close_any()
		_check(Game.state.has_met(npc), npc + " met")
		if npc == "npc_lumi":
			# The lamp reaction belongs to the story scenario; mark it seen so episodes can start.
			Game.state.set_flag("lumi_lamp_reaction_seen")
	_check_eq(Game.state.residents_met(), 16, "16 residents met")
	await _shot("cc05_greetings")
	# Personal episodes, offered by the resident and finished at the real target.
	var done := 0
	for round in 3:
		for id in Game.data.quest_order:
			var q: Dictionary = Game.data.quests[id]
			if q.get("kind", "quest") != "episode" or not Game.quest_available(id):
				continue
			await _accept_offer(str(q["giver"]), id)
			var f0: int = Game.state.relation(q["giver"])["friendship"]
			await _finish_task(id, done % 2)
			_check_eq(QuestBook.state_of(Game.state, id), QuestBook.COMPLETED, id + " completed in play")
			_check_eq(int(Game.state.relation(q["giver"])["friendship"]), mini(100, f0 + 8), id + " friendship +8")
			done += 1
	_check_eq(done, 32, "32 episodes finished in play")
	_check_eq(Game.state.abilities_unlocked.size(), 8, "8 abilities unlocked through episodes")
	_check_ledger()


## Goes to a task's target (resident or object), picks option `pick` (or the hand-over) and
## reads the response.
func _finish_task(id: String, pick: int) -> void:
	var q: Dictionary = Game.data.quests[id]
	var target := str(q["target"])
	if Game.data.npcs.has(target):
		await _talk_npc(target)
	else:
		await _use(target, _location_of(target))
	await _read_to_choices()
	var options: Array = []
	for i in main.dialogue._choices.size():
		var c: Dictionary = main.dialogue._choices[i]
		if c.get("action", "") == "complete_quest" and str(c.get("arg", "")).get_slice("|", 0) == id:
			options.append(i)
	_check(not options.is_empty(), "%s can be finished at %s" % [id, target])
	if options.is_empty():
		await _close_any()
		return
	main.dialogue.choice_buttons[options[mini(pick, options.size() - 1)]].pressed.emit()
	await _frames(2)
	await _close_any()


func _location_of(object_id: String) -> String:
	for loc_id in Game.data.locations:
		for it in Game.data.locations[loc_id].get("interactables", []):
			if it["id"] == object_id:
				return loc_id
	return ""


## Talks to a resident until entry `want` shows (other one-time lines may come first).
func _talk_until(npc: String, want: String, tries: int = 4) -> void:
	for i in tries:
		await _talk_npc(npc)
		if main.last_entry_id == want:
			return
		await _close_any()
	_check_eq(main.last_entry_id, want, "%s eventually says %s" % [npc, want])


# --- cc06: relationships ----------------------------------------------------------------------

func _cc06() -> void:
	await _new_game("관계")
	_setup_open_town()
	for npc in Game.data.npc_order:
		Game.state.relation(npc)["met"] = true
	for f in ["intro_met_lumi", "moa_met", "sera_met", "lumi_lamp_reaction_seen"]:
		Game.state.set_flag(f)
	for id in ["npc_kyle.bond_01", "npc_lumi.bond_01", "npc_moa.bond_01"]:
		Game.state.quests[id] = QuestBook.COMPLETED
	# Kyle's second episode through play, then a rivalry scene that leaves friendship alone.
	await _accept_offer("npc_kyle", "npc_kyle.bond_02")
	await _finish_task("npc_kyle.bond_02", 0)
	var fk: int = Game.state.relation("npc_kyle")["friendship"]
	await _talk_until("npc_kyle", "kyle_rivalry")
	await _close_any()
	_check_eq(int(Game.state.relation("npc_kyle")["rivalry"]), 10, "rivalry +10")
	_check_eq(int(Game.state.relation("npc_kyle")["friendship"]), fk, "friendship unchanged by rivalry")
	# Romance: offered only to a close friend (friendship 30, set here; the paths to it are in
	# cc05/react) and not on the same day as the second episode. Opt in, dates, together, end it.
	Game.state.relation("npc_kyle")["friendship"] = 30
	fk = 30
	await _next_day()
	await _talk_until("npc_kyle", "kyle.romance_offer", 6)
	await _choose_text("더 알아가고")
	await _close_any()
	for want in ["kyle.date1", "kyle.date2"]:
		await _talk_until("npc_kyle", want)
		await _close_any()
	await _talk_until("npc_kyle", "kyle.decide")
	await _choose_text("함께")
	await _close_any()
	_check_eq(Game.state.relation("npc_kyle")["romance"]["stage"], "committed", "together")
	await _shot("cc06_together")
	await _talk_until("npc_kyle", "kyle.together")
	await _choose_text("정리")
	await _close_any()
	_check_eq(Game.state.relation("npc_kyle")["romance"]["stage"], "closed", "ended")
	_check(not Game.state.relation("npc_kyle")["romance"]["consent"], "consent withdrawn")
	_check_eq(int(Game.state.relation("npc_kyle")["friendship"]), fk, "friendship stays after ending")
	# Declining: Lumi stays a friend and never asks again.
	await _accept_offer("npc_lumi", "npc_lumi.bond_02")
	await _finish_task("npc_lumi.bond_02", 1)
	Game.state.relation("npc_lumi")["friendship"] = 30
	var fl: int = Game.state.relation("npc_lumi")["friendship"]
	await _next_day()
	await _talk_until("npc_lumi", "lumi.romance_offer", 6)
	await _choose_text("친구로")
	await _close_any()
	_check_eq(Game.state.relation("npc_lumi")["romance"]["stage"], "closed", "declined")
	_check_eq(int(Game.state.relation("npc_lumi")["friendship"]), fl, "declining costs nothing")
	for i in 3:
		await _talk_npc("npc_lumi")
		_check(not main.last_entry_id.begins_with("lumi.romance") and not main.last_entry_id.begins_with("lumi.date"), "no pressure after declining")
		await _close_any()
	# A resident pair bonded by an episode, and the other resident notices.
	await _accept_offer("npc_moa", "npc_moa.bond_02")
	await _finish_task("npc_moa.bond_02", 1)
	_check_eq(Game.state.edge_phase("moa_nora"), "bonded", "Moa and Nora bonded")
	await _talk_until("npc_nora", "nora_moa_edge")
	await _close_any()
	_check_ledger()


# --- cc07: house and town projects --------------------------------------------------------

## Money for long-loop features comes from a single visible ledger entry ("test_grant"); the
## real earning loop is covered by story/cc03 and the unit tests.
func _grant_test_chips(n: int) -> void:
	Game.state.add_chips(n, "test_grant")
	Game.save_game()


func _choose_arg(action: String, arg: String) -> void:
	await _read_to_choices()
	if action == "start_poker" and Game.debug_deck_queue.is_empty():
		Game.debug_deck_queue = [DECKS["win"]]
	var choices: Array = main.dialogue._choices
	for i in choices.size():
		if choices[i].get("action", "") == action and str(choices[i].get("arg", "")) == arg:
			main.dialogue.choice_buttons[i].pressed.emit()
			await _frames(2)
			return
	_check(false, "choice %s(%s) not offered" % [action, arg])


func _fund(pid: String) -> void:
	await _use("project_board", "community_hall")
	await _choose_arg("fund_project", pid)
	await _close_any()
	_check(Game.state.project_done(pid), pid + " funded in play")


func _upgrade_home(stage: int) -> void:
	await _use("home_blueprint", "player_home")
	await _read_to_choices()
	if not main.dialogue._choices.any(func(c): return c.get("action", "") == "upgrade_home"):
		_check(false, "blueprint offers no upgrade: %s (chips %d)" % [main.dialogue._lines, Game.state.chips_balance])
		await _close_any()
		return
	await _choose("upgrade_home")
	# The house reloads, then says what changed.
	for i in 240:
		if main.ui_mode == "dialogue" and main.world != null and main.world.location_id == "player_home":
			break
		await _frames(1)
	_check(main.dialogue._lines.size() > 0 and main.dialogue.visible, "upgrade explains what changed")
	await _close_any()
	_check_eq(Game.state.home_stage, stage, "house stage %d" % stage)


func _place_in_room(room: String, decorate_id: String, item_id: String) -> String:
	await _travel(room)
	await _go_to("home_edit", decorate_id)
	await _press("interact")
	_check_eq(main.ui_mode, "home_edit", "decorating " + room)
	var slot := ""
	for s in Game.home_slots(room):
		if Game.state.placement_at(s["id"]) == "":
			slot = s["id"]
			break
	_check(main.home_edit.item_buttons.has(item_id), "%s listed in %s" % [item_id, room])
	if slot == "" or not main.home_edit.item_buttons.has(item_id):
		main.home_edit.close_button.pressed.emit()
		await _frames(2)
		return ""
	main.home_edit.item_buttons[item_id].pressed.emit()
	await _frames(1)
	main.home_edit.slot_buttons[slot].pressed.emit()
	await _frames(1)
	main.home_edit.confirm_button.pressed.emit()
	await _frames(2)
	_check_eq(Game.state.placement_at(slot), item_id, "%s placed in %s" % [item_id, slot])
	# The same slot cannot take a second item.
	main.home_edit.slot_buttons[slot].pressed.emit()
	await _frames(1)
	_check(main.home_edit.confirm_button.disabled, "occupied slot cannot be filled again")
	main.home_edit.close_button.pressed.emit()
	await _frames(2)
	return slot


func _cc07() -> void:
	await _new_game("집과 마을")
	_setup_open_town()
	for pid in ["board_restoration", "guest_cottage"]:
		Game.state.projects.erase(pid)
	_grant_test_chips(2000)
	var start: int = Game.state.chips_balance
	# Blueprint explains the first condition before any project or episode.
	await _use("home_blueprint", "player_home")
	_check(main.dialogue.current_line().contains("조건"), "blueprint shows the condition")
	await _close_any()
	# Projects in unlock order, each with a visible change.
	await _fund("board_restoration")
	_check(Conditions.check({"project_complete": "board_restoration"}, Game.state), "workshop unlocked")
	await _travel("workshop")
	_check(main.world.npc_nodes.has("npc_bibi"), "Bibi works inside the workshop now")
	await _upgrade_home(1)
	await _fund("square_seating")
	await _travel("village_square")
	_check(Game.state.owned_count("item.memento.05_08") == 1, "seating memento")
	await _shot("cc07_square_seating")
	Game.state.set_flag("story.act2_started")
	await _fund("guest_cottage")
	await _travel("guest_cottage")
	_check(main.world.npc_nodes.has("npc_sia"), "Sia moved into the guest cottage")
	await _fund("market_awning")
	_check(Game.shop_items("bibi_workshop").has("item.furniture.07_01"), "awning brings new workshop furniture")
	Game.state.quests["npc_nora.bond_01"] = QuestBook.COMPLETED
	await _fund("postbox_garden")
	Game.state.quests["npc_haru.bond_01"] = QuestBook.COMPLETED
	await _fund("lantern_path")
	Game.state.set_flag("story.act2_complete")
	await _fund("card_room_extension")
	await _rest_until("evening")
	await _travel("card_room")
	var practice: Dictionary = main.world.find_interactable("poker_table", "practice_table")
	_check(not practice.is_empty() and Conditions.check(practice["conditions"], Game.state), "practice table in the card room")
	Game.state.set_flag("story.act3_started")
	await _fund("festival_decor")
	_check_eq(Game.state.projects.size(), 8, "all 8 projects complete")
	# Funding twice is impossible: the board lists it as done.
	await _use("project_board", "community_hall")
	await _read_to_choices()
	var again := false
	for c in main.dialogue._choices:
		again = again or c.get("action", "") == "fund_project"
	_check(not again, "nothing left to fund")
	await _close_any()
	# House: stages 2 and 3, rooms open, one item placed in every room.
	await _rest_until("day")
	await _upgrade_home(2)
	await _upgrade_home(3)
	for item in ["item.furniture.01_01", "item.decor.01_04", "item.furniture.02_02"]:
		Game.state.grant_item(item)
	var slots := {}
	slots["player_home"] = await _place_in_room("player_home", "home_decorate", "item.furniture.01_01")
	slots["player_home_annex"] = await _place_in_room("player_home_annex", "annex_decorate", "item.decor.01_04")
	slots["player_home_hall"] = await _place_in_room("player_home_hall", "hall_decorate", "item.memento.05_08")
	await _shot("cc07_hall")
	var costs := 0
	for st in Game.data.home["stages"]:
		costs += int(st["cost"])
	for pid in Game.data.project_order:
		costs += int(Game.data.projects[pid]["cost"])
	_check_eq(start - Game.state.chips_balance, costs, "every house stage and project paid exactly once")
	# Placements survive a save and continue.
	main.return_to_title()
	await _frames(3)
	main.title.continue_button.pressed.emit()
	await _wait_world("player_home_hall")
	for room in slots:
		_check(slots[room] != "" and Game.state.placement_at(slots[room]) != "", "placement in %s kept" % room)
	_check_ledger()


# --- life: odd jobs and requests -------------------------------------------------------------

func _life() -> void:
	await _new_game("생활")
	_setup_open_town()
	for f in ["story.act2_started", "story.act2_complete", "story.act3_started"]:
		Game.state.set_flag(f)
	Game.state.day_count += 1  # festival requests open the morning after act 2
	Game.state.quests.erase("quest.sera_delivery")
	# Plaza job (board), letter delivery (postbox), shelving (shop), lantern check (grove).
	await _start_job()
	for spot in Game.job.remaining():
		await _collect_spot(spot)
	_check_eq(Game.state.jobs_completed, 1, "plaza job done")
	await _use("postbox", "residential")
	await _choose_arg("start_job", "job.post_delivery")
	_check(Game.job != null and Game.job.job_type == "deliver", "letter job started")
	var to: String = Game.job.recipient
	await _talk_npc(to)
	_check(Game.job != null, "travelling does not cancel the letter job")
	await _read_to_choices()
	await _choose("job_deliver")
	await _close_any()
	_check_eq(Game.state.jobs_completed, 2, "letter delivered to " + to)
	await _use("shop_shelves", "small_shop")
	await _choose_arg("start_job", "job.shop_shelving")
	for i in 3:
		await _use("shop_shelves", "small_shop")
		var need: String = Game.job.next_shelf_good()
		var wrong: String = "리본" if need != "리본" else "찻잔"
		if i == 0:
			await _choose_arg("shelve", wrong)
			_check_eq(Game.job.done_count(), 0, "wrong good is refused")
		await _choose_arg("shelve", need)
		await _close_any()
	_check_eq(Game.state.jobs_completed, 3, "shelving done")
	await _use("lantern_path_marker", "grove")
	await _choose_arg("start_job", "job.lantern_check")
	var spots: Array = Game.job.remaining()
	await _collect_spot(spots[0])
	var before: int = Game.state.chips_balance
	await _travel("village_square")
	_check(Game.job == null, "leaving the grove cancels the lantern check")
	_check_eq(Game.state.chips_balance, before, "no pay for a cancelled run")
	await _use("lantern_path_marker", "grove")
	await _choose_arg("start_job", "job.lantern_check")
	for spot in Game.job.remaining():
		await _collect_spot(spot)
	_check_eq(Game.state.jobs_completed, 4, "lantern check done on a new run")
	# Sera's first request comes from her own dialogue (D4); the other 15 are offered by residents.
	await _talk_npc("npc_sera")
	await _choose_arg("dialogue", "sera_quest_offer")
	await _choose_arg("accept_quest", "quest.sera_delivery")
	await _finish_task("quest.sera_delivery", 0)
	var done := 1
	for round in 3:
		for id in Game.data.quest_order:
			var q: Dictionary = Game.data.quests[id]
			if q.get("kind", "quest") != "quest" or not Game.quest_available(id):
				continue
			var chips0: int = Game.state.chips_balance
			await _accept_offer(str(q["giver"]), id)
			_check(main.hud.quest_text().contains(str(q["name"])) or Game.state.tracked_quest != id, id + " shown in the HUD")
			await _finish_task(id, 0)
			_check_eq(Game.state.chips_balance - chips0, int(q["reward"]), id + " reward once")
			done += 1
	_check_eq(done, 16, "16 requests finished in play")
	_check_ledger()


# --- cc08: poker opponents, abilities, modes and the tournament ----------------------------------

## After a table or invitation opened the setup: picks the opponent (when asked) and the ability.
## After a table or invitation: picks the opponent when the table asks, then carries `ability`
## (swapped at the table; there is no separate loadout step). Hands started straight from a
## dialogue choice get their stacked deck from _choose_arg.
func _pick_loadout(mode: String, opponent: String, ability: String, deck: String = "win", expect_table: bool = true) -> void:
	if main.ui_mode == "dialogue":
		Game.debug_deck_queue = [DECKS[deck]]
		await _read_to_choices()
		var first := "%s|%s|" % [mode, opponent]
		for c in main.dialogue._choices:
			if str(c.get("arg", "")) == first:
				await _choose_arg("poker_loadout", first)
				break
	if expect_table:
		_check_eq(main.ui_mode, "poker", "%s hand against %s started" % [mode, opponent])
	if main.ui_mode == "poker" and ability != "" and main.poker.match_ref.ability_id != ability:
		main.poker.select_ability(ability)
		_check_eq(main.poker.match_ref.ability_id, ability, "carrying " + ability)


## Plays the dealt hand by standing and checks the per-hand bookkeeping.
func _stand_and_check(opponent: String, expect: String) -> void:
	var r0: Dictionary = Game.state.relation(opponent).duplicate(true)
	var hist0: int = Game.state.poker_history.get(opponent, []).size()
	var chips0: int = Game.state.chips_balance
	var f0: int = r0["friendship"]
	_check(main.poker._header.text.contains(Game.data.npc_name(opponent)) or main.poker.hand_stake() == 0, "header names " + opponent)
	main.poker.stand_button.pressed.emit()
	await _frames(2)
	_check_eq(PokerEconomy.outcome_key(main.poker.match_ref.outcome), expect, "outcome vs " + opponent)
	var line: String = Game.opponent_line(opponent, expect)
	_check(main.poker._result_line.text.contains(line), opponent + " speaks their own line")
	if main.poker.hand_stake() > 0:
		var prizes := int(main.poker.last_result.get("first_win_bonus", 0)) + int(main.poker.last_result.get("round_prize", 0))
		_check_eq(Game.state.chips_balance - chips0, {"win": 40, "draw": 20, "lose": 0}[expect] + prizes, "payout vs " + opponent)
		_check_eq(int(Game.state.relation(opponent)["poker_hands"]), int(r0["poker_hands"]) + 1, "hand counted with " + opponent)
		_check_eq(int(Game.state.relation(opponent)["rivalry"]), mini(100, int(r0["rivalry"]) + 5), "rivalry +5 with " + opponent)
		_check_eq(int(Game.state.relation(opponent)["friendship"]), f0, "friendship untouched by poker")
		_check_eq(Game.state.poker_history.get(opponent, []).size(), mini(10, hist0 + 1), "public history recorded")
	_check(Game.state.poker_in_progress.is_empty(), "nothing pending after the showdown")


func _leave_table() -> void:
	main.poker.result_leave_button.pressed.emit()
	await _frames(3)
	_check_eq(main.ui_mode, "world", "back from the table")


func _cc08() -> void:
	await _new_game("카드")
	_setup_open_town()
	for npc in Game.data.npc_order:
		Game.state.relation(npc)["met"] = true
	for f in ["intro_met_lumi", "moa_met", "sera_met", "lumi_lamp_reaction_seen", "story.act2_started", "story.act2_complete",
			"story.act3_started", "story.festival_ready", "story.act3_complete", "story.postgame"]:
		Game.state.set_flag(f)
	for a in Game.data.abilities:
		if not Game.state.abilities_unlocked.has(a):
			Game.state.abilities_unlocked.append(a)
	_grant_test_chips(1000)
	# Practice: free, from the notice board, nothing changes but the lesson.
	var chips0: int = Game.state.chips_balance
	var ledger0: int = Game.state.chips_ledger.size()
	await _go_to("job_board", "job_board")
	await _press("interact")
	await _choose_arg("start_poker", "practice|")
	await _pick_loadout("practice", "", "ability.suit_echo")
	_check(main.poker._header.text.contains("연습"), "practice header")
	main.poker.ability_button.pressed.emit()
	await _frames(1)
	_check(main.poker._ability_label.text.contains("문양"), "suit echo shown")
	await _stand_and_check("npc_moa", "win")
	_check(main.poker._result_detail.text.contains("연습"), "practice result says no chips")
	_check_eq(Game.state.chips_balance, chips0, "practice keeps chips")
	_check_eq(Game.state.chips_ledger.size(), ledger0, "practice writes no ledger line")
	_check_eq(Game.state.poker_hands_completed, 0, "practice is not a counted hand")
	await _leave_table()
	# Social mix at the square (evenings): seven residents, one ability each.
	await _rest_until("evening")
	var social := {"npc_rira": "ability.star_sense", "npc_taeo": "ability.discard_hint", "npc_ella": "ability.steady_hand",
		"npc_haru": "ability.table_read", "npc_yul": "ability.lucky_mark", "npc_sia": "ability.friendly_pause", "npc_juno": "ability.pattern_book"}
	for npc in social:
		await _use("square_mix_table", "village_square")
		await _pick_loadout("social_mix", npc, social[npc])
		await _try_ability(social[npc])
		await _stand_and_check(npc, "win")
		_check(main.poker._result_line.text.split("\n").size() >= 2, "spectators react at the social mix")
		await _shot("cc08_social_" + npc)
		await _leave_table()
	# Friendly challenge at the card garden.
	for npc in ["npc_lumi", "npc_kyle", "npc_ren"]:
		await _use("garden_table", "waterfront")
		await _pick_loadout("friendly_challenge", npc, "ability.star_sense", "lose")
		await _stand_and_check(npc, "lose")
		await _leave_table()
	# Table read now has public history with Rira.
	await _use("square_mix_table", "village_square")
	await _pick_loadout("social_mix", "npc_rira", "ability.table_read")
	main.poker.ability_button.pressed.emit()
	await _frames(1)
	_check(main.poker._ability_label.text.contains("지난 판"), "table read uses the public record")
	await _stand_and_check("npc_rira", "win")
	await _leave_table()
	# Card-room home game by invitation, twice more against Kyle -> his poker rivalry scene.
	await _rest_until("evening")
	for i in 2:
		await _talk_until_choice("npc_kyle", "start_poker")
		await _choose_arg("start_poker", "homegame|npc_kyle")
		await _pick_loadout("homegame", "npc_kyle", "ability.star_sense")
		await _stand_and_check("npc_kyle", "win")
		await _leave_table()
	_check_eq(int(Game.state.relation("npc_kyle")["poker_hands"]), 3, "three hands with Kyle")
	await _talk_until("npc_kyle", "kyle_rivalry")
	await _close_any()
	# Home game in the house's gathering room.
	Game.state.home_stage = 3
	await _rest_until("day")
	await _use("home_table", "player_home_hall")
	await _pick_loadout("homegame", "npc_lumi", "ability.star_sense")
	# Ability used, then the game is closed from the menu: same hand, same result, no second use.
	main.poker.ability_button.pressed.emit()
	await _frames(1)
	var seen_text: String = main.poker._ability_label.text
	var hand: Array = _codes(main.poker.match_ref.player_hand)
	var stakes := _ledger_count("poker_stake")
	main.return_to_title()
	await _frames(3)
	main.title.continue_button.pressed.emit()
	for i in 240:
		if main.ui_mode == "poker":
			break
		await _frames(1)
	_check_eq(main.ui_mode, "poker", "hand resumes after quitting")
	_check_eq(_codes(main.poker.match_ref.player_hand), hand, "same cards")
	_check_eq(main.poker._ability_label.text, seen_text, "same ability result")
	_check(main.poker.ability_button.disabled, "ability stays used")
	_check_eq(main.poker.match_ref.mode, "homegame", "same table")
	_check_eq(_ledger_count("poker_stake"), stakes, "no second stake")
	await _stand_and_check("npc_lumi", "win")
	await _leave_table()
	# Folding in the game is the only way to lose a stake without a showdown.
	await _use("home_table", "player_home_hall")
	await _pick_loadout("homegame", "npc_lumi", "ability.star_sense")
	var before_fold: int = Game.state.chips_balance
	main.poker.leave_button.pressed.emit()
	await _frames(1)
	main.poker.confirm_leave_button.pressed.emit()
	await _frames(3)
	_check_eq(Game.state.chips_balance, before_fold, "fold returns nothing")
	_check_eq(int(Game.state.poker_record.get("fold", 0)), 1, "fold recorded")
	_check(Game.state.poker_in_progress.is_empty(), "folded hand is gone")
	# Tournament at the festival booth: three rounds, retry after a loss, resume mid-round,
	# reward once.
	await _rest_until("evening")
	await _use("festival_booth", "village_square")
	await _choose_arg("start_poker", "tournament|")
	await _pick_loadout("tournament", "npc_ren", "ability.star_sense")
	await _stand_and_check("npc_ren", "win")
	_check_eq(int(Game.state.tournament["stage"]), 1, "round 2 next")
	_check(Game.state.get_flag("festival.qualifier_seen"), "qualifier remembered")
	Game.debug_deck_queue = [DECKS["lose"]]
	main.poker.again_button.pressed.emit()
	await _frames(2)
	_check_eq(main.poker.match_ref.opponent_id, "npc_rira", "round 2 against Rira")
	await _stand_and_check("npc_rira", "lose")
	_check_eq(int(Game.state.tournament["stage"]), 1, "a loss keeps the round")
	Game.debug_deck_queue = [DECKS["win"]]
	main.poker.again_button.pressed.emit()
	await _frames(2)
	main.return_to_title()
	await _frames(3)
	main.title.continue_button.pressed.emit()
	for i in 240:
		if main.ui_mode == "poker":
			break
		await _frames(1)
	_check_eq(main.poker.match_ref.mode, "tournament", "tournament hand resumes")
	_check_eq(main.poker.match_ref.opponent_id, "npc_rira", "same round after restarting")
	await _stand_and_check("npc_rira", "win")
	Game.debug_deck_queue = [DECKS["win"]]
	main.poker.again_button.pressed.emit()
	await _frames(2)
	await _stand_and_check("npc_kyle", "win")
	_check(Game.state.get_flag("festival.tournament_won"), "tournament won")
	_check_eq(Game.state.owned_count("item.card_back.08_06"), 1, "winner's card back")
	_check(main.poker._result_detail.text.contains("우승"), "winner message")
	await _shot("cc08_tournament")
	await _leave_table()
	# Playing it again gives no second reward.
	for npc in ["npc_ren", "npc_rira", "npc_kyle"]:
		await _use("festival_booth", "village_square")
		await _choose_arg("start_poker", "tournament|")
		await _pick_loadout("tournament", npc, "ability.star_sense")
		await _stand_and_check(npc, "win")
		await _leave_table()
	_check_eq(Game.state.owned_count("item.card_back.08_06"), 1, "reward only once")
	# Equip the won card back: the table shows it.
	await _open_menu_collection("card_back")
	main.menu.equip_buttons["item.card_back.08_06"].pressed.emit()
	await _frames(2)
	_check_eq(Game.state.equipped.get("card_back", ""), "item.card_back.08_06", "card back equipped")
	main.menu.resume_button.pressed.emit()
	await _frames(2)
	_check_ledger()


## Uses the loaded ability in the way it is meant (some need a selection first).
func _try_ability(ability: String) -> void:
	match ability:
		"ability.steady_hand":
			main.poker.player_views[3].pressed.emit(3)
			main.poker.player_views[4].pressed.emit(4)
			await _frames(1)
			main.poker.ability_button.pressed.emit()
			await _frames(1)
			_check(main.poker._selected.is_empty(), "steady hand undid the selection")
		"ability.lucky_mark":
			main.poker.ability_button.pressed.emit()
			await _frames(1)
			main.poker.player_views[0].pressed.emit(0)
			await _frames(1)
			_check_eq(main.poker.match_ref.locked_index, 0, "card 1 marked")
			main.poker.player_views[0].pressed.emit(0)
			await _frames(1)
			_check(not main.poker._selected.has(0), "marked card cannot be selected")
		"ability.friendly_pause":
			main.poker.ability_button.pressed.emit()
			await _frames(1)
			_check(main.poker._help_panel.visible, "help opened")
		_:
			main.poker.ability_button.pressed.emit()
			await _frames(1)
	_check(main.poker._ability_label.text != "", ability + " says something")
	_check(main.poker.ability_button.disabled, ability + " used once")


func _open_menu_collection(cat: String) -> void:
	main.open_menu()
	await _frames(2)
	main.menu.collection_button.pressed.emit()
	await _frames(1)
	main.menu.show_collection(cat)
	await _frames(1)


# --- cc09: quitting and restoring anywhere -------------------------------------------------------

func _quit_and_continue(expect_loc: String) -> void:
	main.return_to_title()
	await _frames(3)
	main.title.continue_button.pressed.emit()
	await _frames(3)
	for i in 240:
		if main.ui_mode == "poker" or (main.ui_mode == "world" and main.world != null and main.world.location_id == expect_loc):
			break
		await _frames(1)
	await _physics(2)


func _cc09() -> void:
	await _new_game("중단")
	_setup_open_town()
	for npc in Game.data.npc_order:
		Game.state.relation(npc)["met"] = true
	for f in ["intro_met_lumi", "moa_met", "sera_met", "lumi_lamp_reaction_seen", "story.act2_started", "story.act2_complete",
			"story.act3_started", "story.festival_ready", "story.act3_complete", "story.postgame"]:
		Game.state.set_flag(f)
	Game.state.home_stage = 3
	for a in Game.data.abilities:
		if not Game.state.abilities_unlocked.has(a):
			Game.state.abilities_unlocked.append(a)
	_grant_test_chips(600)
	# Every place: quit from the menu and continue at the same spot and time.
	for time in ["day", "evening"]:
		await _rest_until(time)
		for loc_id in Game.data.locations:
			if loc_id == "card_room" and time == "day":
				continue
			await _travel(loc_id)
			var pos: Vector2 = main.world.player.position
			await _quit_and_continue(loc_id)
			_check_eq(main.world.location_id, loc_id, "%s restored (%s)" % [loc_id, time])
			_check(main.world.player.position.distance_to(pos) < 4.0, "%s same spot" % loc_id)
			_check_eq(Game.state.time_of_day, time, "%s same time" % loc_id)
	# A hand in every mode survives a quit: same cards, same deck, no second stake.
	var tables := [
		["practice", "", "village_square", "job_board", "start_poker", "practice|"],
		["social_mix", "npc_taeo", "village_square", "square_mix_table", "", ""],
		["friendly_challenge", "npc_ren", "waterfront", "garden_table", "", ""],
		["homegame", "npc_lumi", "player_home_hall", "home_table", "", ""],
		["tournament", "npc_ren", "village_square", "festival_booth", "start_poker", "tournament|"],
	]
	for t in tables:
		await _use(t[3], t[2])
		if t[4] != "":
			await _choose_arg(t[4], t[5])
		await _pick_loadout(t[0], t[1], "ability.star_sense")
		main.poker.ability_button.pressed.emit()
		await _frames(1)
		var hand: Array = _codes(main.poker.match_ref.player_hand)
		var deck: Array = main.poker.match_ref.deck.codes()
		var stakes := _ledger_count("poker_stake")
		var chips: int = Game.state.chips_balance
		var said: String = main.poker._ability_label.text
		await _quit_and_continue(t[2])
		_check_eq(main.ui_mode, "poker", t[0] + " hand resumes")
		_check_eq(main.poker.match_ref.mode, t[0], t[0] + " same table")
		_check_eq(_codes(main.poker.match_ref.player_hand), hand, t[0] + " same cards")
		_check_eq(main.poker.match_ref.deck.codes(), deck, t[0] + " no reshuffle")
		_check_eq(main.poker._ability_label.text, said, t[0] + " same ability result")
		_check_eq(_ledger_count("poker_stake"), stakes, t[0] + " no second stake")
		_check_eq(Game.state.chips_balance, chips, t[0] + " no refund")
		await _stand_and_check(Game.match_opponent(main.poker.match_ref), "win")
		await _leave_table()
	# An odd job interrupted by quitting pays nothing and can be started again.
	await _rest_until("day")
	await _travel("village_square")
	await _start_job()
	await _collect_spot(Game.job.remaining()[0])
	var before_job: int = Game.state.chips_balance
	await _quit_and_continue("village_square")
	_check(Game.job == null, "an unfinished job does not survive quitting")
	_check_eq(Game.state.chips_balance, before_job, "and pays nothing")
	await _start_job()
	for spot in Game.job.remaining():
		await _collect_spot(spot)
	_check_eq(Game.state.chips_balance, before_job + 10, "a new run pays once")
	# Funding a project and quitting at once: done once, paid once.
	Game.state.projects.erase("square_seating")
	var chips_before: int = Game.state.chips_balance
	await _fund("square_seating")
	await _quit_and_continue("community_hall")
	_check(Game.state.project_done("square_seating"), "project kept after quitting")
	_check_eq(Game.state.chips_balance, chips_before - int(Game.data.projects["square_seating"]["cost"]), "paid once")
	_check_eq(Game.state.owned_count("item.memento.05_08"), 1, "project gift once")
	# An accepted request stays active across a restart.
	Game.state.quests.erase("quest.ren_cardcase")
	await _accept_offer("npc_ren", "quest.ren_cardcase")
	await _quit_and_continue(main.world.location_id)
	_check_eq(QuestBook.state_of(Game.state, "quest.ren_cardcase"), QuestBook.ACTIVE, "request still active")
	_check(main.hud.quest_text().contains(str(Game.data.quests["quest.ren_cardcase"]["name"])), "HUD still tracks it")
	_check_ledger()


# --- cc10: saves from earlier builds ---------------------------------------------------------------

func _cc10() -> void:
	# A v3 save (first-play build) in the middle of a card-room hand.
	var m := PokerMatch.new(Deck.stacked(DECKS["win"]))
	var hand := m.to_dict()
	for k in ["mode", "opponent_id", "persona", "ability_id", "stake", "locked_index", "place"]:
		hand.erase(k)
	var v3 := {
		"save_version": 3, "player_name": "셋째", "chips_balance": 73,
		"chips_ledger": [{"seq": 1, "delta": 93, "reason": "starting_chips", "balance": 93}, {"seq": 2, "delta": -20, "reason": "poker_stake", "balance": 73}],
		"flags": {"intro_met_lumi": true, "moa_met": true, "sera_met": true, "lumi_lamp_reaction_seen": true, "tutorial_done": true, "sera_quest_thanked": true},
		"poker_hands_completed": 2, "poker_record": {"win": 1, "draw": 0, "lose": 1, "fold": 0},
		"owned_items": {}, "collection": ["furniture.lamp_small"],
		"home_placements": [{"slot": "slot_window", "item": "furniture.lamp_small"}],
		"current_scene": "card_room", "player_position": [480, 560], "time_of_day": "evening",
		"quests": {"quest.sera_delivery": "completed"}, "pending_poker_stake": 20, "jobs_completed": 3,
		"poker_in_progress": hand,
	}
	_write_save(JSON.stringify(v3))
	main.show_title()
	await _frames(2)
	main.title.continue_button.pressed.emit()
	for i in 240:
		if main.ui_mode == "poker":
			break
		await _frames(1)
	_check_eq(main.ui_mode, "poker", "v3 hand resumes")
	_check_eq(_codes(main.poker.match_ref.player_hand), WIN_PLAYER, "same v3 cards")
	_check_eq(Game.state.chips_balance, 73, "v3 balance kept")
	_check_eq(main.poker.match_ref.mode, "homegame", "v3 hand is the card-room home game")
	_check_eq(Game.match_opponent(main.poker.match_ref), "npc_lumi", "against Lumi as before")
	_check_eq(int(_saved().get("save_version", -1)), GameState.SAVE_VERSION, "rewritten as the current version")
	main.poker.stand_button.pressed.emit()
	await _frames(2)
	_check_eq(Game.state.chips_balance, 113, "win pays 40 once")
	_check_eq(_ledger_count("poker_stake"), 1, "no second stake")
	await _leave_table()
	_check(Game.state.is_item_placed("furniture.lamp_small"), "lamp still placed")
	_check(Game.state.has_met("npc_lumi") and Game.state.has_met("npc_moa") and Game.state.has_met("npc_sera"), "met residents kept")
	_check_eq(QuestBook.state_of(Game.state, "quest.sera_delivery"), QuestBook.COMPLETED, "request kept")
	_check_eq(Game.state.jobs_completed, 3, "job count kept")
	# The old player continues straight into the new story.
	await _talk_npc("npc_moa")
	_check_eq(main.last_entry_id, "scn.missing_invitation", "act 1 opens for an old save")
	await _choose_text("찾아볼게요")
	_check(Game.state.get_flag("story.act1_started"), "act 1 started")
	_check_ledger()
	# A v3 save with a stake but no cards is damaged (R2 exception is v2-only) and left untouched.
	var broken := v3.duplicate(true)
	broken["poker_in_progress"] = {}
	var text := JSON.stringify(broken)
	_write_save(text)
	main.show_title()
	await _frames(2)
	main.title.continue_button.pressed.emit()
	await _frames(4)
	_check_eq(main.ui_mode, "title", "damaged v3 save refused")
	_check_eq(FileAccess.get_file_as_string(Game.save_path), text, "file left as it was")


# --- cc11: the collection ------------------------------------------------------------------------

func _cc11() -> void:
	await _new_game("수집")
	_setup_open_town()
	for npc in Game.data.npc_order:
		Game.state.relation(npc)["met"] = true
	for f in ["intro_met_lumi", "moa_met", "sera_met"]:
		Game.state.set_flag(f)
	Game.state.projects.erase("board_restoration")
	Game.state.projects.erase("guest_cottage")
	for f in ["story.clue_postbox", "story.clue_grove", "story.act1_complete"]:
		Game.state.set_flag(f, false)
	for a in Game.data.abilities:
		if not Game.state.abilities_unlocked.has(a):
			Game.state.abilities_unlocked.append(a)
	_grant_test_chips(6000)
	# Mementos from their own scenes (each scene jumped to with the story flags it needs;
	# the whole chain in order is cc01).
	await _use("grove_sign_west", "grove")
	await _close_any()
	await _use("grove_sign_east", "grove")
	await _close_any()
	await _use("postbox_stamp_spot", "residential")
	await _close_any()
	await _use("card_room_board", "village_square")
	await _choose_text("친구와")
	await _choose_text("좋아요")
	for f in ["story.act2_heard_lumi", "story.act2_heard_kyle", "story.act2_prep_done"]:
		Game.state.set_flag(f)
	await _talk_npc("npc_lumi")
	await _choose_text("친목")
	await _choose_text("좋아요")
	await _fund("board_restoration")
	await _fund("square_seating")
	Game.state.contributions = ["prep:juno", "prep:spectate", "quest:quest.festival_letters"]
	await _use("hall_meeting", "community_hall")
	await _choose_text("다이아")
	await _rest_until("evening")
	await _use("festival_booth", "village_square")
	await _choose_text("정리")
	await _choose_text("계속 둘러보기")
	await _choose_text("좋은 저녁")
	await _use("lantern_path_marker", "grove")
	_check_eq(main.last_entry_id, "evt_sky_lantern", "sky lantern evening")
	await _close_any()
	# Tournament card back.
	for npc in ["npc_ren", "npc_rira", "npc_kyle"]:
		await _use("festival_booth", "village_square")
		await _choose_arg("start_poker", "tournament|")
		await _pick_loadout("tournament", npc, "ability.star_sense")
		main.poker.stand_button.pressed.emit()
		await _frames(2)
		await _leave_table()
	await _rest_until("day")
	await _talk_until("npc_lumi", "scn.postgame_lumi")
	await _close_any()
	for i in 8:
		_check(Game.state.collection.has("item.memento.0%d_08" % (i + 1)), "memento %d from its scene" % (i + 1))
	_check(Game.state.collection.has("item.card_back.08_06"), "tournament card back")
	# Everything the shops sell, bought through the shop screen.
	Game.state.projects["market_awning"] = "complete"
	var shops := [["npc_sera", "sera_shop", ""], ["npc_bibi", "bibi_workshop", ""], ["npc_taeo", "taeo_tailor", ""], ["npc_ren", "swap_shop", ""]]
	for sh in shops:
		await _open_shop_via(sh[0], sh[1])
		for item_id in Game.shop_items(sh[1]):
			if Game.state.owned_count(item_id) == 0 and main.shop.buy_buttons.has(item_id):
				main.shop.buy_buttons[item_id].pressed.emit()
				await _frames(1)
		main.shop.close()
		await _frames(2)
	# Show every placeable item in the house once, then put it back; wear every wearable once.
	await _travel("player_home")
	await _go_to("home_edit", "home_decorate")
	await _press("interact")
	var shown := 0
	for id in Game.data.item_order:
		if not Game.is_placeable(id):
			continue
		if Game.state.owned_count(id) <= 0:
			continue
		main.home_edit.item_buttons[id].pressed.emit()
		await _frames(1)
		main.home_edit.slot_buttons["slot_table"].pressed.emit()
		await _frames(1)
		main.home_edit.confirm_button.pressed.emit()
		await _frames(1)
		_check_eq(Game.state.placement_at("slot_table"), id, id + " on display")
		main.home_edit.slot_buttons["slot_table"].pressed.emit()
		await _frames(1)
		main.home_edit.store_button.pressed.emit()
		await _frames(1)
		_check(Game.state.collection.has(id), id + " stays in the book")
		shown += 1
	main.home_edit.close_button.pressed.emit()
	await _frames(2)
	var worn := 0
	for cat in DataDB.EQUIP_CATEGORIES:
		await _open_menu_collection(cat)
		for id in Game.data.item_order:
			if str(Game.data.items[id]["category"]) != cat or not main.menu.equip_buttons.has(id):
				continue
			main.menu.equip_buttons[id].pressed.emit()
			await _frames(1)
			_check_eq(Game.state.equipped.get(cat, ""), id, id + " worn")
			worn += 1
		main.menu.resume_button.pressed.emit()
		await _frames(2)
	var placeable := Game.data.item_order.filter(func(id): return Game.is_placeable(id)).size()
	_check_eq(shown, placeable, "every placeable item shown in the house")
	_check_eq(worn, 24, "every clothing, card back and chip style worn")
	# Trades: buy the second copy of each traded item at Sera's, then exchange at the stall.
	await _open_shop_via("npc_sera", "sera_shop")
	for t in Game.data.trades:
		main.shop.buy_buttons[t["give"]].pressed.emit()
		await _frames(1)
		_check(Game.state.owned_count(t["give"]) >= 2, "second %s bought" % t["give"])
	main.shop.close()
	await _frames(2)
	for t in Game.data.trades:
		await _use("swap_stall", "market")
		await _choose_arg("trade", t["id"])
		_check(Game.state.events_done.has("trade:" + str(t["id"])), t["id"] + " traded")
	_check_eq(Game.state.collection.size(), Game.data.item_order.size(), "every item found (%d)" % Game.data.item_order.size())
	for id in Game.data.item_order:
		_check(Game.state.collection.has(id), id + " in the book")
	await _open_menu_collection("memento")
	_check(main.menu._book_title.text.contains("%d / %d" % [Game.data.item_order.size(), Game.data.item_order.size()]), "book complete")
	await _shot("cc11_book")
	main.menu.resume_button.pressed.emit()
	await _frames(2)
	_check_ledger()


## Talks to a shop owner until the shop choice is offered (one-time lines may come first).
func _open_shop_via(npc: String, shop_id: String) -> void:
	for i in 5:
		await _talk_npc(npc)
		await _read_to_choices()
		for c in main.dialogue._choices:
			if c.get("action", "") == "open_shop" and c.get("arg", "") == shop_id:
				await _choose_arg("open_shop", shop_id)
				_check_eq(main.ui_mode, "shop", shop_id + " open")
				return
		await _close_any()
	_check(false, "%s never offered %s" % [npc, shop_id])


# --- cc12: time changes, missed events, festival again ---------------------------------------

func _cc12() -> void:
	await _new_game("시간")
	_setup_open_town()
	for f in ["story.act1_started", "story.clue_postbox", "story.clue_grove", "story.act1_complete"]:
		Game.state.set_flag(f, false)
	Game.state.set_flag("intro_met_lumi")
	Game.state.set_flag("lumi_lamp_reaction_seen")
	# Declining a story scene does not lose it.
	await _talk_npc("npc_moa")
	await _close_any()
	await _talk_npc("npc_moa")
	_check_eq(main.last_entry_id, "scn.missing_invitation", "invitation offered")
	await _choose_text("나중에요")
	await _rest_until("evening")
	await _rest_until("day")
	await _talk_npc("npc_moa")
	_check_eq(main.last_entry_id, "scn.missing_invitation", "offered again after a day passes")
	await _choose_text("찾아볼게요")
	# The act 2 meeting is a daytime scene; in the evening Lumi says when to come.
	for f in ["story.act1_complete", "story.act2_started", "story.act2_heard_lumi", "story.act2_heard_kyle", "story.act2_prep_done"]:
		Game.state.set_flag(f)
	Game.state.relation("npc_kyle")["met"] = true
	await _rest_until("evening")
	await _talk_until("npc_lumi", "scn.act2_evening_hint")
	_check_eq(main.world.location_id, "card_room", "Lumi in the card room at night")
	await _close_any()
	await _rest_until("day")
	await _talk_npc("npc_lumi")
	_check_eq(main.world.location_id, "waterfront", "Lumi at the waterfront by day")
	_check_eq(main.last_entry_id, "scn.two_tables_argument_lumi", "the scene was not missed")
	await _choose_text("규칙 설명")
	await _choose_text("좋아요")
	# The festival waits: skipped in the day, slept through, still there in the evening.
	Game.state.contributions = ["prep:juno", "prep:spectate", "quest:quest.festival_lights"]
	await _use("hall_meeting", "community_hall")
	await _choose_text("스페이드")
	await _use("festival_booth", "village_square")
	_check_eq(main.last_entry_id, "scn.fourleaf_wait", "booth waits for the evening")
	await _choose_text("나중에")
	await _rest_until("evening")
	await _rest_until("day")
	await _rest_until("evening")
	await _use("festival_booth", "village_square")
	_check(main.last_entry_id.begins_with("scn.fourleaf_evening"), "festival still ready after a missed evening")
	await _choose_text("정리")
	await _choose_text("계속 둘러보기")
	await _choose_text("좋은 저녁")
	_check(Game.state.get_flag("story.act3_complete"), "festival held")
	# Holding it again: more evenings, never a second memento.
	for i in 2:
		await _use("festival_booth", "village_square")
		_check(main.last_entry_id.begins_with("festival_booth_again"), "festival again (%s)" % main.last_entry_id)
		await _choose_text("정리 돕기")
		await _close_any()
	_check_eq(Game.state.owned_count("item.memento.04_08"), 1, "helper memento once")
	# Everyone can still be found after the story, at both times.
	for time in ["day", "evening"]:
		await _rest_until(time)
		for npc in ["npc_lumi", "npc_kyle", "npc_moa", "npc_juno"]:
			await _talk_npc(npc)
			_check_eq(main.ui_mode, "dialogue", "%s reachable (%s)" % [npc, time])
			await _close_any()
	_check_ledger()


# --- react: the 12 cross-system reactions in play (06_integration/01) ----------------------------
# 1 (lamp -> Lumi) and 11-12 (festival) are played in cc01; 2-10 here.

func _react() -> void:
	await _new_game("반응")
	Game.state.set_flag("tutorial_done")
	main.tutorial.visible = false
	for a in Game.data.abilities:
		if not Game.state.abilities_unlocked.has(a):
			Game.state.abilities_unlocked.append(a)
	# 2. The parcel: Sera asks, Lumi receives and thanks, Sera thanks afterwards.
	await _talk_npc("npc_sera")
	await _choose_arg("dialogue", "sera_quest_offer")
	await _choose_arg("accept_quest", "quest.sera_delivery")
	await _finish_task("quest.sera_delivery", 0)
	await _talk_until("npc_sera", "sera_quest_done")
	await _close_any()
	# 3. A plaza job, then Miri at the hall has noticed.
	await _travel("village_square")
	await _start_job()
	for spot in Game.job.remaining():
		await _collect_spot(spot)
	await _talk_npc("npc_miri")
	await _close_any()
	await _talk_until("npc_miri", "miri_cleanup_praise")
	await _close_any()
	# Scene gates for the rest (story order is cc01): prologue and act 1 done, chips for projects.
	for f in ["intro_met_lumi", "lumi_lamp_reaction_seen", "story.prologue_complete", "story.act1_started", "story.clue_postbox", "story.clue_grove", "story.act1_complete", "story.act2_started", "story.act2_heard_lumi"]:
		Game.state.set_flag(f)
	_grant_test_chips(1500)
	# 4. Three card-room hands with Lumi (any result) -> her rivalry line.
	await _rest_until("evening")
	for i in 3:
		for t in 4:
			await _talk_npc("npc_lumi")
			await _read_to_choices()
			if main.dialogue._choices.any(func(c): return c.get("action", "") == "start_poker" and str(c.get("arg", "")) == ""):
				break
			await _close_any()
		Game.debug_deck_queue = [DECKS["lose" if i == 1 else "win"]]
		await _choose_arg("start_poker", "")
		await _pick_loadout("homegame", "", "ability.star_sense")
		main.poker.stand_button.pressed.emit()
		await _frames(2)
		await _leave_table()
	await _talk_until("npc_lumi", "lumi_rivalry")
	await _close_any()
	await _next_day()  # act 2 opens the morning after act 1
	# 5. Talking with Kyle changes how Lumi wants to run the gathering.
	await _talk_npc("npc_kyle")
	await _close_any()
	await _talk_until("npc_kyle", "scn.kyle_view")
	await _close_any()
	await _talk_until("npc_lumi", "lumi_after_kyle")
	await _close_any()
	await _rest_until("day")
	# 7. Board restoration opens the workshop: Sera's stock line, Bibi inside.
	await _fund("board_restoration")
	await _talk_until("npc_sera", "sera_town")
	await _close_any()
	await _travel("workshop")
	_check(main.world.npc_nodes.has("npc_bibi"), "Bibi in the workshop")
	await _talk_npc("npc_bibi")
	await _close_any()
	await _talk_until("npc_bibi", "bibi_town")
	await _close_any()
	# 6. The postbox garden: Nora and Moa move there and talk about it.
	Game.state.quests["npc_nora.bond_01"] = QuestBook.COMPLETED
	await _fund("postbox_garden")
	await _travel("residential")
	_check(main.world.npc_nodes.has("npc_moa") and main.world.npc_nodes["npc_moa"].position == Vector2(820, 320), "Moa by the garden")
	_check(main.world.npc_nodes["npc_nora"].position == Vector2(640, 300), "Nora by the garden")
	await _talk_until("npc_moa", "moa_town")
	await _close_any()
	await _talk_until("npc_nora", "nora_town")
	await _close_any()
	# 8. The lantern path: Haru and Ona talk about the walk.
	Game.state.quests["npc_haru.bond_01"] = QuestBook.COMPLETED
	await _fund("lantern_path")
	await _talk_npc("npc_haru")
	await _close_any()
	await _talk_until("npc_haru", "haru_town")
	await _close_any()
	await _talk_npc("npc_ona")
	await _close_any()
	await _talk_until("npc_ona", "ona_town")
	await _close_any()
	# 9. A bigger house: Yul comes to check the door frames.
	await _upgrade_home(1)
	await _upgrade_home(2)
	await _talk_npc("npc_yul")
	await _close_any()
	await _talk_until("npc_yul", "yul_home_visit")
	await _close_any()
	# 10. A social game at the tea house: Rira and Taeo grow closer.
	Game.state.set_flag("story.act2_complete")  # the act 2 preparation offer would come first otherwise
	await _rest_until("evening")
	for npc in ["npc_rira", "npc_taeo"]:
		await _talk_npc(npc)
		await _close_any()
	await _use("tea_social_table", "tea_house")
	await _pick_loadout("social_mix", "npc_taeo", "ability.star_sense")
	_check_eq([main.poker.match_ref.mode, main.poker.match_ref.place], ["social_mix", "tea_house"], "social game at the tea house")
	main.poker.stand_button.pressed.emit()
	await _frames(2)
	await _leave_table()
	_check(Game.state.get_flag("tea.social_played"), "tea social remembered")
	await _talk_until("npc_rira", "rira_tea_social")
	await _close_any()
	_check_eq(Game.state.edge_phase("rira_taeo"), "bonded", "Rira and Taeo bonded")
	await _talk_until("npc_taeo", "taeo_rira_edge")
	await _close_any()
	await _shot("react_tea")
	_check_ledger()


# --- savefail: a failed save rolls the change back (v0.3.1) ------------------------------------

func _state_key() -> String:
	var d: Dictionary = Game.state.to_dict()
	d.erase("player_position")
	d.erase("current_scene")
	return JSON.stringify(d)


## Makes the next save fail and remembers the state and the save file as they are now.
func _arm() -> Array:
	Game.debug_fail_saves = 1
	return [_state_key(), FileAccess.get_file_as_string(Game.save_path)]


func _rolled_back(before: Array, label: String) -> void:
	_check_eq(Game.debug_fail_saves, 0, label + ": the save was attempted")
	_check(Game.last_commit_failed, label + ": reported as rolled back")
	_check_eq(_state_key(), before[0], label + ": state exactly as before")
	_check_eq(FileAccess.get_file_as_string(Game.save_path), before[1], label + ": save file untouched")


func _savefail() -> void:
	await _new_game("저장")
	Game.state.set_flag("tutorial_done")
	main.tutorial.visible = false
	for a in Game.data.abilities:
		if not Game.state.abilities_unlocked.has(a):
			Game.state.abilities_unlocked.append(a)
	Game.save_game()
	# Odd job: the last pickup is undone, unpaid; picking it up again pays once.
	await _start_job()
	var spots: Array = Game.job.remaining()
	await _collect_spot(spots[0])
	await _collect_spot(spots[1])
	var b := _arm()
	await _collect_spot(spots[2])
	_rolled_back(b, "job")
	_check(Game.job != null and Game.job.remaining() == [spots[2]], "job: last spot back on the ground")
	await _collect_spot(spots[2])
	_check_eq(Game.state.chips_balance, 50, "job: paid once (40 + 10)")
	# Purchase.
	await _open_shop_via("npc_sera", "sera_shop")
	b = _arm()
	main.shop.buy_buttons[LAMP].pressed.emit()
	await _frames(1)
	_rolled_back(b, "purchase")
	_check(main.shop._message.text.contains("저장하지 못해서"), "purchase: shop says so")
	main.shop.buy_buttons[LAMP].pressed.emit()
	await _frames(1)
	_check_eq([Game.state.owned_count(LAMP), Game.state.chips_balance], [1, 0], "purchase: once")
	main.shop.close()
	await _frames(2)
	# Placement and storage.
	await _travel("player_home")
	await _go_to("home_edit", "home_decorate")
	await _press("interact")
	main.home_edit.item_buttons[LAMP].pressed.emit()
	main.home_edit.slot_buttons["slot_window"].pressed.emit()
	b = _arm()
	main.home_edit.confirm_button.pressed.emit()
	await _frames(1)
	_rolled_back(b, "place")
	_check(main.home_edit._status.text.contains("저장하지 못해서"), "place: panel says so")
	main.home_edit.confirm_button.pressed.emit()
	await _frames(1)
	_check(Game.state.is_item_placed(LAMP), "place: placed on retry")
	main.home_edit.slot_buttons["slot_window"].pressed.emit()
	b = _arm()
	main.home_edit.store_button.pressed.emit()
	await _frames(1)
	_rolled_back(b, "store")
	_check(Game.state.is_item_placed(LAMP), "store: still placed")
	main.home_edit.close_button.pressed.emit()
	await _frames(2)
	# Request accept and completion with its reward.
	await _talk_npc("npc_sera")
	await _choose_arg("dialogue", "sera_quest_offer")
	b = _arm()
	await _choose_arg("accept_quest", "quest.sera_delivery")
	_rolled_back(b, "accept")
	await _talk_npc("npc_sera")
	await _choose_arg("dialogue", "sera_quest_offer")
	await _choose_arg("accept_quest", "quest.sera_delivery")
	_check_eq(QuestBook.state_of(Game.state, "quest.sera_delivery"), QuestBook.ACTIVE, "accept: on retry")
	await _talk_npc("npc_lumi")
	await _read_to_choices()
	b = _arm()
	await _choose("complete_quest")
	await _close_any()
	_rolled_back(b, "request")
	_check_eq(QuestBook.state_of(Game.state, "quest.sera_delivery"), QuestBook.ACTIVE, "request: still to deliver")
	await _finish_task("quest.sera_delivery", 0)
	_check_eq(_ledger_count("quest:quest.sera_delivery"), 1, "request: paid once")
	# Project funding and the house (chips from a visible test line, not part of the economy audit).
	_grant_test_chips(400)
	Game.state.set_flag("story.act1_started")
	await _use("project_board", "community_hall")
	b = _arm()
	await _choose_arg("fund_project", "board_restoration")
	await _close_any()
	_rolled_back(b, "project")
	await _fund("board_restoration")
	_check_eq(_ledger_count("project:board_restoration"), 1, "project: paid once")
	await _use("home_blueprint", "player_home")
	await _read_to_choices()
	b = _arm()
	await _choose("upgrade_home")
	await _close_any()
	_rolled_back(b, "house")
	await _upgrade_home(1)
	_check_eq(_ledger_count("home:home_cozy"), 1, "house: paid once")
	# Trade and equipment.
	await _open_shop_via("npc_sera", "sera_shop")
	for i in 2:
		main.shop.buy_buttons["item.furniture.01_01"].pressed.emit()
		await _frames(1)
	main.shop.close()
	await _frames(2)
	Game.state.projects["square_seating"] = "complete"  # the stall opens with two projects
	await _use("swap_stall", "market")
	b = _arm()
	await _choose_arg("trade", "trade_stools")
	_rolled_back(b, "trade")
	await _use("swap_stall", "market")
	await _choose_arg("trade", "trade_stools")
	_check_eq([Game.state.owned_count("item.furniture.01_01"), Game.state.owned_count("item.card_back.02_06")], [0, 1], "trade: once")
	await _open_menu_collection("card_back")
	b = _arm()
	main.menu.equip_buttons["item.card_back.02_06"].pressed.emit()
	await _frames(1)
	_rolled_back(b, "equip")
	main.menu.equip_buttons["item.card_back.02_06"].pressed.emit()
	await _frames(1)
	_check_eq(Game.state.equipped.get("card_back", ""), "item.card_back.02_06", "equip: on retry")
	main.menu.resume_button.pressed.emit()
	await _frames(2)
	# One-time event reward.
	for npc in ["npc_ella", "npc_ona", "npc_kyle", "npc_moa"]:
		Game.state.relation(npc)["met"] = true
	Game.save_game()
	await _rest_until("evening")
	await _travel("grove")
	b = _arm()
	await _use("lantern_path_marker", "grove")
	await _close_any()
	_rolled_back(b, "event")
	_check_eq(Game.state.owned_count("item.memento.08_08"), 0, "event: no memento yet")
	await _use("lantern_path_marker", "grove")
	await _close_any()
	await _use("lantern_path_marker", "grove")
	await _close_any()
	_check_eq(Game.state.owned_count("item.memento.08_08"), 1, "event: memento once")
	# Poker: stake, fold, settlement with retry, tournament reward.
	await _travel("card_room")
	var chips0: int = Game.state.chips_balance
	await _talk_until_choice("npc_lumi", "start_poker")
	b = _arm()
	await _choose_arg("start_poker", "")
	await _pick_loadout("homegame", "", "ability.star_sense", "win", false)
	_check_eq(main.ui_mode, "world", "stake: no table")
	_rolled_back(b, "stake")
	await _talk_until_choice("npc_lumi", "start_poker")
	await _choose_arg("start_poker", "")
	await _pick_loadout("homegame", "", "ability.star_sense")
	_check_eq(Game.state.chips_balance, chips0 - 20, "stake: once")
	b = _arm()
	main.poker.leave_button.pressed.emit()
	await _frames(1)
	main.poker.confirm_leave_button.pressed.emit()
	await _frames(2)
	_rolled_back(b, "fold")
	_check_eq(main.ui_mode, "poker", "fold: still at the table")
	b = _arm()
	main.poker.stand_button.pressed.emit()
	await _frames(2)
	_rolled_back(b, "settle")
	_check(main.poker.save_retry and main.poker.result_leave_button.disabled, "settle: retry offered, leaving blocked")
	_check_eq(Game.state.pending_poker_stake, 20, "settle: the stake is still on the table")
	main.poker.again_button.pressed.emit()
	await _frames(2)
	_check(not main.poker.save_retry, "settle: saved on retry")
	_check_eq(Game.state.chips_balance, chips0 + 20 + int(main.poker.last_result.get("first_win_bonus", 0)), "settle: paid once (+40 on a 20 stake, plus a first-win prize)")
	_check_eq(_ledger_count("poker_payout_win"), 1, "settle: one payout line")
	await _leave_table()
	for f in ["story.act3_started", "story.festival_ready", "story.act3_complete"]:
		Game.state.set_flag(f)
	Game.state.tournament["stage"] = 2
	Game.save_game()
	await _travel("village_square")
	await _use("festival_booth", "village_square")
	await _choose_arg("start_poker", "tournament|")
	await _pick_loadout("tournament", "npc_kyle", "ability.star_sense")
	b = _arm()
	main.poker.stand_button.pressed.emit()
	await _frames(2)
	_rolled_back(b, "tournament")
	_check_eq(Game.state.owned_count("item.card_back.08_06"), 0, "tournament: no reward yet")
	main.poker.again_button.pressed.emit()
	await _frames(2)
	_check_eq(Game.state.owned_count("item.card_back.08_06"), 1, "tournament: reward once")
	await _leave_table()
	# What is on disk matches what is in memory.
	var disk: Dictionary = SaveSystem.load_state(Game.save_path)["state"].to_dict()
	var mem: Dictionary = Game.state.to_dict()
	for k in ["player_position", "current_scene"]:
		disk.erase(k)
		mem.erase(k)
	_check_eq(JSON.stringify(disk), JSON.stringify(mem), "save file equals the game state")
	_check_ledger()


func _talk_until_choice(npc: String, action: String) -> void:
	for t in 5:
		await _talk_npc(npc)
		await _read_to_choices()
		if main.dialogue._choices.any(func(c): return c.get("action", "") == action):
			return
		await _close_any()
	_check(false, "%s never offered %s" % [npc, action])


# --- economy: long progression with real earnings only (v0.3.1) ---------------------------------
# One new save per run, no test_grant: the same Game actions the screens call (jobs, requests,
# episodes, story dialogue, shop, projects, house, poker). Policy: advance the story whenever
# possible, take every request and episode as it opens, buy the next unlocked goal as soon as it is
# affordable, otherwise earn with odd jobs in rotation (plaza, letters, shelves, lanterns). The mixed
# run also plays one card-room hand before each job while it has 20 chips (seeded decks).

const ECON_GOALS := [
	["lamp", ""], ["project", "board_restoration"], ["home", "1"], ["project", "postbox_garden"],
	["project", "lantern_path"], ["project", "square_seating"], ["project", "guest_cottage"],
	["project", "market_awning"], ["home", "2"], ["project", "card_room_extension"], ["home", "3"],
	["project", "festival_decor"],
]
const ECON_JOBS := ["job.plaza_cleanup", "job.post_delivery", "job.shop_shelving", "job.lantern_check"]

var _econ := {}
var _econ_rng := RandomNumberGenerator.new()


func _economy() -> void:
	var results := {"no_poker": await _econ_run(false, 2031)}
	for seed in [2031, 7, 99, 404, 1234]:
		results["mixed_%d" % seed] = await _econ_run(true, seed)
	var f := FileAccess.open("user://economy_audit.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("[economy] " + JSON.stringify(results))


func _econ_run(mixed: bool, seed: int) -> Dictionary:
	await _new_game("경제")
	Game.state.set_flag("tutorial_done")
	main.tutorial.visible = false
	_econ = {"jobs": {}, "job_runs": 0, "requests": 0, "episodes": 0, "poker_hands": 0, "scenes": 0, "rests": 0, "milestones": {}}
	_econ_rng.seed = seed
	# A new player walks around and greets everyone once (no chips involved).
	for npc in Game.data.npc_order:
		if not Game.state.has_met(npc):
			_api_say(npc)
	var goals := ECON_GOALS.duplicate(true)
	var steps := 0
	while not goals.is_empty() and steps < 3000:
		steps += 1
		_econ_story()
		_econ_tasks()
		var bought := false
		for g in goals:
			if not _econ_unlocked(g):
				continue
			if _econ_cost(g) <= Game.state.chips_balance:
				_econ_buy(g)
				goals.erase(g)
				bought = true
			break
		if bought:
			continue
		if mixed and Game.can_join_poker():
			_econ_poker()
		_econ_job(ECON_JOBS[_econ["job_runs"] % ECON_JOBS.size()])
	_econ_story()
	_check(goals.is_empty(), "%s: every goal reached with real earnings (%s left)" % ["mixed" if mixed else "no poker", goals])
	_check_eq(_ledger_count("test_grant"), 0, "no test_grant line")
	_check_ledger()
	if not mixed:
		_check_eq(Game.state.poker_hands_completed, 0, "no-poker run played no hand")
	_check(Game.state.get_flag("story.postgame"), "story finished along the way")
	_econ["final"] = _econ_snapshot()
	return _econ


func _econ_snapshot() -> Dictionary:
	var earned := 0
	var spent := 0
	var poker_net := 0
	for e in Game.state.chips_ledger:
		var d := int(e["delta"])
		if d > 0:
			earned += d
		else:
			spent -= d
		if str(e["reason"]).begins_with("poker_"):
			poker_net += d
	return {
		"job_runs": _econ["job_runs"], "jobs": _econ["jobs"].duplicate(), "requests": _econ["requests"],
		"episodes": _econ["episodes"], "poker_hands": _econ["poker_hands"], "story_scenes": _econ["scenes"],
		"rests": _econ["rests"], "earned": earned, "spent": spent, "poker_net": poker_net,
		"balance": Game.state.chips_balance, "projects": Game.state.projects.size(), "home_stage": Game.state.home_stage,
		"act": _econ_act(),
	}


func _econ_act() -> String:
	for f in ["story.postgame", "story.act3_complete", "story.act2_complete", "story.act1_complete", "story.prologue_complete"]:
		if Game.state.get_flag(f):
			return f
	return "start"


func _econ_milestone(name: String) -> void:
	if not _econ["milestones"].has(name):
		_econ["milestones"][name] = _econ_snapshot()


func _econ_unlocked(g: Array) -> bool:
	match g[0]:
		"lamp":
			return true
		"project":
			return Game.project_status(g[1]) == "available"
		"home":
			return Game.state.home_stage == int(g[1]) - 1 and Conditions.check(Game.home_stage_def(int(g[1])).get("unlock", {}), Game.state)
	return false


func _econ_cost(g: Array) -> int:
	match g[0]:
		"lamp":
			return Game.data.item_price(LAMP)
		"project":
			return int(Game.data.projects[g[1]]["cost"])
		"home":
			return int(Game.home_stage_def(int(g[1]))["cost"])
	return 0


func _econ_buy(g: Array) -> void:
	match g[0]:
		"lamp":
			_check(Game.buy_item(LAMP)["ok"], "lamp bought")
			_check(Game.place_item("slot_window", LAMP), "lamp placed")
			_econ_milestone("lamp")
		"project":
			_check(Game.fund_project(g[1])["ok"], g[1] + " funded")
			if Game.state.projects.size() == Game.data.project_order.size():
				_econ_milestone("all_projects")
		"home":
			_check(Game.upgrade_home()["ok"], "house stage " + g[1])
			_econ_milestone("home_" + g[1])


func _econ_job(job_id: String) -> void:
	if not Game.start_job(job_id):
		return
	var run: PlazaJob = Game.job
	match run.job_type:
		"collect":
			for spot in run.remaining():
				Game.collect_job_spot(spot)
		"deliver":
			Game.job_step("deliver", run.recipient)
		"shelve":
			for i in 3:
				Game.job_step("shelve", run.next_shelf_good())
	_check(Game.job == null, job_id + " finished")
	_econ["job_runs"] += 1
	_econ["jobs"][job_id] = int(_econ["jobs"].get(job_id, 0)) + 1


## One card-room hand: the player replaces cards by the same public rule the residents use.
func _econ_poker() -> void:
	Game.debug_deck_queue = [Deck.shuffled(_econ_rng.randi()).codes()]
	var m: PokerMatch = Game.create_poker_match("homegame")
	if m == null:
		return
	m.player_draw(PokerAI.choose_discards(m.player_hand.duplicate(), m.max_discards))
	_check(Game.settle_match(m)["ok"], "hand settled")
	_econ["poker_hands"] += 1


func _econ_tasks() -> void:
	for id in Game.data.quest_order:
		var q: Dictionary = Game.data.quests[id]
		if not Game.quest_available(id):
			continue
		if not Game.accept_quest(id):
			continue
		var arg: String = id + ("|0" if q.get("options", []).size() > 0 else "")
		if Game.complete_quest(arg)["ok"]:
			_econ["requests" if q.get("kind", "quest") == "quest" else "episodes"] += 1


func _econ_set_time(t: String) -> void:
	if Game.state.time_of_day != t:
		Game.set_time(t)
		_econ["rests"] += 1


func _speaker_loc(speaker: String) -> String:
	if speaker.begins_with("obj:"):
		return _location_of(speaker.substr(4))
	return str(Game.npc_place(speaker).get("loc", ""))


## Talks through the data dialogue with the same effects the screens apply; `picks` choose by text,
## otherwise a plain goodbye. Returns the first entry id.
func _api_say(speaker: String, picks: Array = []) -> String:
	var loc := _speaker_loc(speaker)
	var entry: Dictionary = Game.resolve_entry(speaker, loc)
	var first := str(entry.get("id", ""))
	var queue := picks.duplicate()
	var n := 0
	while not entry.is_empty() and n < 8:
		n += 1
		var eff: Array = []
		for fl in entry.get("set_flags", []):
			eff.append({"type": "flag", "flag": fl})
		eff.append_array(entry.get("effects", []))
		if not eff.is_empty() or entry.get("once", false):
			Game.run_effects(eff, DialogueResolver.once_key(entry) if entry.get("once", false) else "")
		var choices: Array = entry.get("choices", []).filter(func(c): return Conditions.check(c.get("conditions", {}), Game.state, loc))
		if choices.is_empty():
			break
		var want: String = queue.pop_front() if not queue.is_empty() else ""
		var chosen: Dictionary = {}
		for c in choices:
			if want != "" and str(c["text"]).contains(want):
				chosen = c
				break
		if chosen.is_empty():
			for c in choices:
				if c.get("action", "") == "close" and c.get("effects", []).is_empty():
					chosen = c
					break
		if chosen.is_empty():
			chosen = choices[0]
		Game.run_effects(chosen.get("effects", []), str(chosen.get("once_key", "")))
		entry = DialogueResolver.find(Game.data.dialogue, chosen["arg"]) if chosen.get("action", "") == "dialogue" else {}
	_econ["scenes"] += 1
	return first


func _api_say_until(speaker: String, want: String, picks: Array = []) -> void:
	for i in 6:
		if str(Game.resolve_entry(speaker, _speaker_loc(speaker)).get("id", "")) == want:
			_api_say(speaker, picks)
			return
		_api_say(speaker)


func _econ_story() -> void:
	var s: GameState = Game.state
	if not s.get_flag("intro_met_lumi"):
		_api_say("npc_lumi")
	if s.is_item_placed(LAMP) and not s.get_flag("lumi_lamp_reaction_seen"):
		_econ_set_time("day")
		_api_say_until("npc_lumi", "lumi_lamp_reaction")
	if s.get_flag("story.prologue_complete") and not s.get_flag("story.act1_started"):
		_econ_set_time("day")
		_api_say_until("npc_moa", "scn.missing_invitation", ["찾아볼게요"])
	if s.get_flag("story.act1_started") and not s.get_flag("story.act1_complete"):
		if not s.get_flag("story.clue_postbox"):
			_api_say("obj:postbox_stamp_spot")
		if not s.get_flag("story.clue_grove"):
			_api_say("obj:grove_sign_west")
			_api_say("obj:grove_sign_east")
		_api_say_until("obj:card_room_board", "scn.board_reopening", ["포커를 몰라도", "좋아요"])
	# Acts open the morning after the previous one: sleep through the waiting day.
	for f in ["story.act1_complete", "story.act2_complete"]:
		if s.get_flag(f) and not Conditions.check({"days_since": {f: 1}}, s):
			_econ_set_time("evening")
			_econ_set_time("day")
	if s.get_flag("story.act2_started") and not s.get_flag("story.act2_complete"):
		_econ_set_time("day")
		if not s.get_flag("story.act2_heard_lumi"):
			_api_say_until("npc_lumi", "scn.lumi_view")
		if not s.get_flag("story.act2_heard_kyle"):
			_api_say_until("npc_kyle", "scn.kyle_view")
		if not s.get_flag("story.act2_prep_done"):
			_api_say_until("npc_rira", "scn.tea_prep_offer", ["찻집 모임"])
			for i in 3:
				_api_say("obj:tea_chair_%d" % (i + 1))
			_api_say_until("npc_rira", "scn.tea_prep_done")
		_api_say_until("npc_lumi", "scn.two_tables_argument_lumi", ["둘 다", "좋아요"])
	if s.get_flag("story.act3_started") and not s.get_flag("story.festival_ready"):
		_econ_set_time("day")
		if not s.contributions.has("prep:juno"):
			_api_say_until("npc_juno", "scn.festival_prep_juno", ["장식"])
		if not s.contributions.has("prep:spectate"):
			_api_say_until("npc_moa", "scn.festival_prep_moa", ["관전"])
		if s.contributions.size() >= 3:
			_api_say_until("obj:hall_meeting", "scn.festival_meeting", ["하트"])
	if s.get_flag("story.festival_ready") and not s.get_flag("story.act3_complete"):
		_econ_set_time("evening")
		_api_say_until("obj:festival_booth", "scn.fourleaf_evening", ["관전", "좋은 저녁"])
	if s.get_flag("story.act3_complete") and not s.get_flag("story.postgame"):
		_econ_set_time("day")
		_api_say_until("npc_lumi", "scn.postgame_lumi")


# --- helpers ------------------------------------------------------------------------------

## Door route from the current location to `dest` over the location data (breadth-first).
func _route(from: String, dest: String) -> Array:
	var prev := {from: null}
	var queue: Array = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == dest:
			break
		var loc: Dictionary = Game.data.locations[cur]
		for group in ["buildings", "gates", "exits"]:
			for d in loc.get(group, []):
				var t := str(d.get("target", ""))
				if t != "" and not prev.has(t):
					prev[t] = {"from": cur, "door": d}
					queue.append(t)
	var hops: Array = []
	var at := dest
	while prev.get(at) != null:
		hops.push_front(prev[at]["door"])
		at = prev[at]["from"]
	return hops


## True when every door on the route to `loc_id` is unlocked right now.
func _reachable(loc_id: String) -> bool:
	var at: String = main.world.location_id
	for door in _route(at, loc_id):
		if not Conditions.check(door.get("unlock", {}), Game.state, at):
			return false
		at = str(door["target"])
	return true


func _travel(dest: String) -> void:
	if main.ui_mode == "dialogue":
		await _close_any(false)
	if main.world.location_id == dest:
		return
	for door in _route(main.world.location_id, dest):
		if not await _through_door(str(door["id"]), str(door["target"])):
			return
	_check_eq(main.world.location_id, dest, "travelled to " + dest)


## Uses a door; a time-gated door is passed with its "wait" choice (as a player would).
func _through_door(door_id: String, target: String) -> bool:
	await _go_to("door", door_id)
	await _press("interact")
	if main.ui_mode == "dialogue":
		var waited := false
		for c in main.dialogue._choices:
			waited = waited or c.get("action", "") == "wait_and_enter"
		_check(waited, "door %s opened (%s)" % [door_id, main.dialogue._lines])
		if not waited:
			await _close_any()
			return false
		await _choose("wait_and_enter")
	await _wait_world(target)
	return true


## Sleeps through to the next morning (acts open a day after the previous one).
func _next_day() -> void:
	await _rest_until("evening")
	await _rest_until("day")


## Sleeps or rests in the player's bed until `time`.
func _rest_until(time: String) -> void:
	if Game.state.time_of_day == time:
		return
	await _travel("player_home")
	await _go_to("rest", "home_bed")
	await _press("interact")
	await _read_to_choices()
	await _choose("set_time")
	await _wait_world("player_home")
	_check_eq(Game.state.time_of_day, time, "rested until " + time)


func _talk_npc(npc_id: String) -> void:
	# A first greeting may have flowed into this resident's waiting scene: it is already open.
	if main.ui_mode == "dialogue" and main.continued_scene and main._dialogue_npc == npc_id:
		main.continued_scene = false
		return
	if main.ui_mode == "dialogue":
		await _close_any(false)
	var place: Dictionary = Game.npc_place(npc_id)
	_check(not place.is_empty(), npc_id + " is somewhere now")
	await _travel(str(place.get("loc", "")))
	await _talk(npc_id)


## Interacts with a world object (by id, any kind) in a location.
func _use(id: String, loc_id: String) -> void:
	if main.ui_mode == "dialogue":
		await _close_any(false)
	await _travel(loc_id)
	var kind := ""
	for it in main.world.interactables:
		if it["id"] == id:
			kind = it["kind"]
	_check(kind != "", "object %s in %s" % [id, loc_id])
	await _go_to(kind, id)
	await _press("interact")


func _accept_offer(npc_id: String, quest_id: String) -> void:
	await _talk_npc(npc_id)
	await _read_to_choices()
	var picked := false
	for i in main.dialogue._choices.size():
		var c: Dictionary = main.dialogue._choices[i]
		if c.get("action", "") == "quest_offer" and c.get("arg", "") == quest_id:
			main.dialogue.choice_buttons[i].pressed.emit()
			picked = true
			await _frames(2)
			break
	_check(picked, "offer for %s shown by %s" % [quest_id, npc_id])
	await _read_to_choices()
	await _choose("accept_quest")
	_check_eq(QuestBook.state_of(Game.state, quest_id), QuestBook.ACTIVE, quest_id + " accepted")


func _choose_text(part: String) -> void:
	await _read_to_choices()
	var choices: Array = main.dialogue._choices
	for i in choices.size():
		if str(choices[i].get("text", "")).contains(part):
			main.dialogue.choice_buttons[i].pressed.emit()
			await _frames(2)
			return
	_check(false, "choice containing '%s' not offered (entry %s)" % [part, main.last_entry_id])


## Closes whatever dialogue/panel is open and returns to the world.
## Closes the open dialogue or panel. A story scene that a first greeting flowed into is left open
## (the caller talks to that resident next) unless `keep_scene` is false.
func _close_any(keep_scene: bool = true) -> void:
	for i in 20:
		if main.ui_mode == "world":
			return
		if keep_scene and main.continued_scene and main.ui_mode == "dialogue":
			return
		if main.ui_mode == "shop":
			main.shop.close()
		elif main.ui_mode == "home_edit":
			main.home_edit.close()
		elif main.ui_mode == "dialogue":
			if main.dialogue.showing_choices():
				var closed := false
				for c in main.dialogue._choices:
					if c.get("action", "close") == "close" and not c.has("effects"):
						await _choose_text(str(c["text"]))
						closed = true
						break
				if not closed:
					main.dialogue.choice_buttons[main.dialogue.choice_buttons.size() - 1].pressed.emit()
			else:
				await _press("interact")
		await _frames(2)
	_check(main.ui_mode == "world", "back in the world (mode %s, entry %s, lines %s, choices %s)" % [main.ui_mode, main.last_entry_id, main.dialogue._lines, main.dialogue._choices.map(func(c): return c.get("text", ""))])


func _approach(target: Dictionary) -> Vector2:
	var pos: Vector2 = target["pos"]
	if str(target["kind"]) == "door" and main.world != null:
		var loc: Dictionary = main.world.loc
		for b in loc.get("buildings", []):
			if b.get("id", "") == target["id"]:
				return pos + Vector2(0, 30)
		var center := Geo.vec(loc["size"]) / 2.0
		return pos + (center - pos).normalized() * 30.0
	if str(target["kind"]) == "npc":
		return super(target)
	if str(target["kind"]) in ["object", "poker_table", "rest", "home_edit"]:
		return pos + Vector2(0, 14)
	return super(target)
