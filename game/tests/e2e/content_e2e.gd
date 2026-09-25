extends "res://tests/e2e/first_play_e2e.gd"
## End-to-end driver for the content v0.3 cases (06_integration/05_ACCEPTANCE_AND_QA_MATRIX).
## Same rules as first_play_e2e.gd: the real Main scene, real input for movement and interaction,
## buttons and cards through the signals a click emits. Travel between places goes through the
## actual doors, gates and exits (route found over the location data, then walked hop by hop).
##   godot --headless --path game -- --e2e=cc04 --save-path=user://e2e_cc04.json
## Scenarios:
##   cc04   every district and functional place: enter, move, interact, return; locked doors;
##          time kept while travelling; save and continue inside a district
##   story  cc01 core: new game, no poker, prologue -> act 1 -> act 2 -> act 3 -> postgame
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
		"story":
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

	# Act 2: two tables.
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

	# Act 3: the festival, prepared without poker.
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
	_check_eq(main.last_entry_id, "scn.fourleaf_evening", "the festival starts")
	await _choose_text("관전")
	await _choose_text("좋은 저녁")
	_check(Game.state.get_flag("story.act3_complete"), "act 3 complete")
	await _shot("story_festival")
	# Postgame: sleep, then Lumi in the morning.
	await _rest_until("day")
	await _talk_npc("npc_lumi")
	_check_eq(main.last_entry_id, "scn.postgame_lumi", "postgame morning scene")
	await _close_any()
	_check(Game.state.get_flag("story.postgame"), "postgame")
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
	# Romance: opt in, two dates, together, then end it kindly.
	await _talk_until("npc_kyle", "kyle.romance_offer")
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
	var fl: int = Game.state.relation("npc_lumi")["friendship"]
	await _talk_until("npc_lumi", "lumi.romance_offer")
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
	await _choose("upgrade_home")
	await _wait_world("player_home")
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
	for f in ["story.act2_started", "story.act3_started"]:
		Game.state.set_flag(f)
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
func _pick_loadout(mode: String, opponent: String, ability: String, deck: String = "win") -> void:
	Game.debug_deck_queue = [DECKS[deck]]
	await _read_to_choices()
	var first := "%s|%s|" % [mode, opponent]
	for c in main.dialogue._choices:
		if str(c.get("arg", "")) == first:
			await _choose_arg("poker_loadout", first)
			break
	await _choose_arg("poker_loadout", "%s|%s|%s" % [mode, opponent, ability])
	_check_eq(main.ui_mode, "poker", "%s hand against %s started" % [mode, opponent])


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
		_check_eq(Game.state.chips_balance - chips0, {"win": 40, "draw": 20, "lose": 0}[expect], "payout vs " + opponent)
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
		await _talk_npc("npc_kyle")
		await _read_to_choices()
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
	var place: Dictionary = Game.npc_place(npc_id)
	_check(not place.is_empty(), npc_id + " is somewhere now")
	await _travel(str(place.get("loc", "")))
	await _talk(npc_id)


## Interacts with a world object (by id, any kind) in a location.
func _use(id: String, loc_id: String) -> void:
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
func _close_any() -> void:
	for i in 20:
		if main.ui_mode == "world":
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
