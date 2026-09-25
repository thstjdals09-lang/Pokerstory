extends "res://tests/test_case.gd"
## Content v0.3 Stage 1–2: the main story as data (flags, clues, contributions, festival) and the
## village map (5 districts, 17 functional places, doors, spawns). The UI path is covered by
## tests/e2e/content_e2e.gd; these checks walk the same dialogue data without the scene tree.

var db := DataDB.new()
var errors: Array = db.load_all("res://data")


func _say(s: GameState, speaker: String, location: String, picks: Array = []) -> Array:
	return talk(db, s, speaker, location, picks)


## First greetings take priority over story scenes; the player simply talks again afterwards.
func _greet(s: GameState, npc: String, location: String) -> void:
	if not s.has_met(npc):
		check_eq(_say(s, npc, location)[0], npc.trim_prefix("npc_") + "_greet", "first greeting " + npc)


func _prologue_done() -> GameState:
	var s := GameState.new()
	s.add_chips(40, "start")
	s.set_flag("intro_met_lumi")
	s.grant_item("furniture.lamp_small")
	s.place_item("slot_window", "furniture.lamp_small")
	return s


func test_content_world_data_is_valid() -> void:
	check_eq(errors, [], "data errors")


func test_five_districts_and_seventeen_places() -> void:
	var districts := {}
	for pid in db.places:
		var pl: Dictionary = db.places[pid]
		districts[pl["district"]] = true
		check(db.locations.has(pl["scene"]), "place %s is played in an existing scene" % pid)
	check_eq(districts.size(), 5, "5 districts")
	check_eq(db.places.size(), 17, "17 functional places")


func test_every_location_is_reachable_and_can_return() -> void:
	# Breadth-first over doors, gates and exits from the square; every door lands on a real spawn.
	var seen := {"village_square": true}
	var queue: Array = ["village_square"]
	while not queue.is_empty():
		var loc_id: String = queue.pop_front()
		var loc: Dictionary = db.locations[loc_id]
		for group in ["buildings", "gates", "exits"]:
			for d in loc.get(group, []):
				if not d.has("target"):
					continue
				var target: Dictionary = db.locations.get(d["target"], {})
				check(target.get("spawns", {}).has(d["spawn"]), "%s -> %s spawn %s" % [loc_id, d["target"], d["spawn"]])
				if not seen.has(d["target"]):
					seen[d["target"]] = true
					queue.append(d["target"])
	check_eq(seen.size(), db.locations.size(), "every location reachable from the square")
	# Every non-square location has a way back out.
	for loc_id in db.locations:
		if loc_id == "village_square":
			continue
		var outs := 0
		for group in ["buildings", "gates", "exits"]:
			outs += db.locations[loc_id].get(group, []).size()
		check(outs > 0, "%s has an exit" % loc_id)


func test_spawns_are_inside_bounds_and_not_inside_solids() -> void:
	for loc_id in db.locations:
		var loc: Dictionary = db.locations[loc_id]
		var size := Geo.vec(loc["size"])
		var inset := float(loc.get("bounds_inset", 20))
		for key in loc.get("spawns", {}):
			var p := Geo.vec(loc["spawns"][key])
			check(p.x > inset and p.y > inset and p.x < size.x - inset and p.y < size.y - inset, "%s spawn %s in bounds" % [loc_id, key])
			for b in loc.get("buildings", []):
				check(not Geo.rect(b["rect"]).has_point(p), "%s spawn %s not inside %s" % [loc_id, key, b.get("id", "")])
			for d in loc.get("decor", []):
				if not d.get("solid", false):
					continue
				if d.has("rect"):
					check(not Geo.rect(d["rect"]).has_point(p), "%s spawn %s not inside decor" % [loc_id, key])
				elif d.has("pos"):
					check(Geo.vec(d["pos"]).distance_to(p) > float(d["r"]), "%s spawn %s not inside round decor" % [loc_id, key])


func test_story_runs_without_poker() -> void:
	var s := _prologue_done()
	check_eq(_say(s, "npc_lumi", "village_square"), ["lumi_lamp_reaction"], "lamp reaction")
	check(s.get_flag("story.prologue_complete"), "prologue complete")
	# Act 1: the missing invitation.
	check_eq(_say(s, "npc_moa", "village_square", ["나중에"]), ["moa_first"], "first greeting comes first")
	check_eq(_say(s, "npc_moa", "village_square", ["찾아볼게요"]), ["scn.missing_invitation"], "then the missing invitation")
	check(s.get_flag("story.act1_started"), "act 1 started")
	check_eq(_say(s, "obj:postbox_stamp_spot", "residential"), ["scn.postbox_discovery", "scn.postbox_envelope"], "postbox clue, envelope back to Moa")
	_say(s, "obj:grove_sign_west", "grove")
	check(not s.get_flag("story.clue_grove"), "one sign is not enough")
	_say(s, "obj:grove_sign_east", "grove")
	check(s.get_flag("story.clue_grove"), "both grove signs read")
	check(s.owned_count("item.memento.01_08") == 1, "clue memento granted once")
	check_eq(_say(s, "obj:card_room_board", "village_square", ["포커를 몰라도"]), ["scn.board_reopening", "scn.board_reopening_answer"], "board reopening")
	check(s.get_flag("story.act1_complete") and s.get_flag("story.act2_started"), "act 1 complete, act 2 started")
	# Act 2: two tables.
	_say(s, "npc_lumi", "village_square")
	_greet(s, "npc_kyle", "card_room")
	_say(s, "npc_kyle", "card_room")
	check(s.get_flag("story.act2_heard_lumi") and s.get_flag("story.act2_heard_kyle"), "both views heard")
	_greet(s, "npc_rira", "tea_house")
	_say(s, "npc_rira", "tea_house", ["찻집 모임"])
	for i in 3:
		_say(s, "obj:tea_chair_%d" % (i + 1), "tea_house")
	_say(s, "npc_rira", "tea_house")
	check(s.get_flag("story.act2_prep_done"), "tea preparation done")
	check_eq(_say(s, "npc_lumi", "waterfront", ["둘 다"])[0], "scn.two_tables_argument_lumi", "argument on the waterfront")
	check(s.get_flag("story.act2_complete") and s.get_flag("story.act3_started") and s.get_flag("story.act2_choice_both"), "act 2 complete with the chosen answer")
	check_eq(s.edge_phase("lumi_kyle"), "reconciled", "Lumi and Kyle reconcile")
	# Act 3: festival contributions without poker.
	_greet(s, "npc_juno", "village_square")
	_say(s, "npc_juno", "village_square", ["장식"])
	_say(s, "npc_moa", "village_square", ["관전"])
	check_eq(s.contributions.size(), 2, "two preparation contributions")
	_say(s, "npc_juno", "village_square", ["장식"])
	check_eq(s.contributions.size(), 2, "the same preparation does not count twice")
	QuestBook.accept(s, "quest.festival_letters")
	QuestBook.complete(s, db.quests["quest.festival_letters"])
	check_eq(s.contributions.size(), 3, "a festival request is the third contribution")
	_say(s, "obj:hall_meeting", "community_hall", ["클로버"])
	check(s.get_flag("story.festival_ready") and s.get_flag("story.festival_suit_clover"), "meeting picks a suit")
	s.time_of_day = "day"
	check_eq(DialogueResolver.resolve(db.dialogue, "obj:festival_booth", "village_square", s)["id"], "scn.fourleaf_wait", "the festival waits for the evening")
	s.time_of_day = "evening"
	_say(s, "obj:festival_booth", "village_square", ["관전"])
	check(s.get_flag("story.act3_complete"), "festival ends by watching")
	check_eq(s.poker_hands_completed, 0, "no poker at all")
	s.time_of_day = "day"
	_say(s, "npc_lumi", "village_square")
	check(s.get_flag("story.postgame"), "postgame morning")
	check_eq(DialogueResolver.resolve(db.dialogue, "obj:festival_booth", "village_square", s)["id"], "festival_booth_again", "the festival can be revisited")


func test_story_goals_follow_each_act() -> void:
	var s := _prologue_done()
	s.set_flag("lumi_lamp_reaction_seen")
	s.set_flag("story.prologue_complete")
	var goal := func() -> String:
		for g in db.goals:
			if Conditions.check(g.get("conditions", {}), s):
				return g["text"]
		return ""
	check(goal.call().contains("모아"), "prologue done -> talk to Moa")
	s.set_flag("story.act1_started")
	check(goal.call().contains("단서"), "act 1 -> clues")
	s.set_flag("story.clue_postbox")
	s.set_flag("story.clue_grove")
	check(goal.call().contains("게시판"), "clues -> board")
	s.set_flag("story.act1_complete")
	s.set_flag("story.act2_started")
	check(goal.call().contains("루미와 카일"), "act 2 -> both views")


func test_v3_save_migrates_to_v4_and_keeps_progress() -> void:
	var path := "user://test_v3_migration.json"
	var v3 := {
		"save_version": 3, "player_name": "셋", "chips_balance": 73,
		"chips_ledger": [{"seq": 1, "delta": 73, "reason": "start", "balance": 73}],
		"flags": {"intro_met_lumi": true, "moa_met": true, "lumi_lamp_reaction_seen": true, "tutorial_done": true},
		"poker_hands_completed": 2, "poker_record": {"win": 1, "draw": 0, "lose": 1, "fold": 0},
		"owned_items": {}, "collection": ["furniture.lamp_small"],
		"home_placements": [{"slot": "slot_window", "item": "furniture.lamp_small"}],
		"current_scene": "village_square", "player_position": [800, 900], "time_of_day": "evening",
		"quests": {"quest.sera_delivery": "completed"}, "pending_poker_stake": 0, "jobs_completed": 3,
		"poker_in_progress": {},
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(v3))
	f.close()
	var r := SaveSystem.load_state(path)
	check(r["ok"], "v3 loads")
	var s: GameState = r["state"]
	check_eq(int(r["original_version"]), 3, "original version reported")
	check_eq(s.chips_balance, 73, "balance kept")
	check(s.is_item_placed("furniture.lamp_small"), "lamp stays placed")
	check_eq(s.quests.get("quest.sera_delivery", ""), "completed", "quest kept")
	check(s.has_met("npc_lumi") and s.has_met("npc_moa") and not s.has_met("npc_sera"), "met residents carried over")
	check(s.get_flag("story.prologue_complete"), "prologue counted for a player who saw the lamp reaction")
	check_eq(s.home_stage, 0, "home starts at stage 0")
	check_eq(s.abilities_unlocked, ["ability.star_sense"], "first ability kept")
	check_eq(s.to_dict()["save_version"], GameState.SAVE_VERSION, "written as the current version")
	SaveSystem.delete(path)
