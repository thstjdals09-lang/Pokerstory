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
	_check_eq(main.ui_mode, "world", "back in the world")


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
