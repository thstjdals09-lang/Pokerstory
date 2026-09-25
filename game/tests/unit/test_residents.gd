extends "res://tests/test_case.gd"
## Content v0.3 Stage 3: 16 residents, one place per time, greetings and daily lines, reactions,
## 32 personal episodes, friendship and rivalry kept apart, opt-in romance for four adults,
## and registered resident pairs that change only through events.

const LEGACY_GREETINGS := {"npc_lumi": "lumi_intro", "npc_moa": "moa_first", "npc_sera": "sera_first"}
const ROMANCE := ["npc_lumi", "npc_kyle", "npc_rira", "npc_taeo"]

var db := DataDB.new()
var errors: Array = db.load_all("res://data")


func _greeting_id(npc: String) -> String:
	return LEGACY_GREETINGS.get(npc, npc.trim_prefix("npc_") + "_greet")


func _met_state() -> GameState:
	var s := GameState.new()
	for npc in db.npc_order:
		s.relation(npc)["met"] = true
	for f in ["intro_met_lumi", "moa_met", "sera_met", "sera_quest_thanked", "lumi_lamp_reaction_seen", "sera_lamp_reaction_seen", "story.prologue_complete"]:
		s.set_flag(f)
	s.quests["quest.sera_delivery"] = QuestBook.COMPLETED
	return s


func _episodes() -> Array:
	return db.quest_order.filter(func(id): return db.quests[id].get("kind", "quest") == "episode")


func test_sixteen_adult_residents_one_place_each() -> void:
	check_eq(errors, [], "data errors")
	check_eq(db.npc_order.size(), 16, "16 residents")
	var s := GameState.new()
	for npc in db.npc_order:
		check(bool(db.npcs[npc].get("adult", false)), npc + " is an adult")
		for time in ["day", "evening"]:
			var place: Dictionary = db.npc_place(npc, time, s)
			check(db.locations.has(place.get("loc", "")), "%s has a %s place" % [npc, time])
	# Overrides replace the place (never a second copy) for every state they depend on.
	var story := _met_state()
	for f in ["story.act2_prep_done", "story.act2_heard_lumi", "story.act2_heard_kyle"]:
		story.set_flag(f)
	check_eq(db.npc_place("npc_lumi", "day", story)["loc"], "waterfront", "Lumi moves to the waterfront for act 2")
	check_eq(db.npc_place("npc_lumi", "evening", story)["loc"], "card_room", "and still has one evening place")
	check_eq(db.npc_place("npc_bibi", "day", s)["loc"], "market", "Bibi waits outside the locked workshop")
	s.projects["board_restoration"] = "complete"
	check_eq(db.npc_place("npc_bibi", "day", s)["loc"], "workshop", "Bibi inside once it opens")


func test_greetings_daily_lines_and_reactions() -> void:
	for npc in db.npc_order:
		var fresh := GameState.new()
		var place: Dictionary = db.npc_place(npc, "day", fresh)
		var first := DialogueResolver.resolve(db.dialogue, npc, place["loc"], fresh)
		check_eq(first.get("id", ""), _greeting_id(npc), npc + " greets first")
		var s := _met_state()
		s.set_flag("story.prologue_complete", false)  # daily lines, not the story's next scene
		for e in db.dialogue:
			if e.get("once", false):
				s.events_done[DialogueResolver.once_key(e)] = true
		for time in ["day", "evening"]:
			s.time_of_day = time
			var loc: String = db.npc_place(npc, time, s)["loc"]
			var e := DialogueResolver.resolve(db.dialogue, npc, loc, s)
			check(not e.is_empty() and int(e.get("priority", 0)) <= 18, "%s has a %s line (%s)" % [npc, time, e.get("id", "")])
		var kinds := {}
		for e in db.dialogue:
			if e.get("npc", "") != npc:
				continue
			for k in ["poker_react", "memory", "town", "festival"]:
				if str(e["id"]).ends_with("_" + k):
					kinds[k] = true
		check_eq(kinds.size(), 4, npc + " reacts to poker, memories, town and festival")


func test_thirty_two_episodes_two_per_resident() -> void:
	var per := {}
	var object_ids := {}
	for loc_id in db.locations:
		for it in db.locations[loc_id].get("interactables", []):
			object_ids[it["id"]] = true
	for id in _episodes():
		var q: Dictionary = db.quests[id]
		per[q["giver"]] = int(per.get(q["giver"], 0)) + 1
		var target := str(q["target"])
		check(db.npcs.has(target) or object_ids.has(target), "%s target %s exists in the world" % [id, target])
		check(q.get("offer_lines", []).size() > 0, id + " has an offer")
	check_eq(_episodes().size(), 32, "32 episodes")
	for npc in db.npc_order:
		check_eq(int(per.get(npc, 0)), 2, npc + " gives two episodes")


func test_every_episode_completes_once_and_rewards_once() -> void:
	var s := _met_state()
	s.grant_item("furniture.lamp_small")
	for f in ["story.act1_started", "story.act1_complete"]:
		s.set_flag(f)
	var done := 0
	for round in 3:
		for id in _episodes():
			var q: Dictionary = db.quests[id]
			if QuestBook.state_of(s, id) != QuestBook.NOT_STARTED or not Conditions.check(q.get("unlock", {}), s):
				continue
			check(QuestBook.accept(s, id), id + " accepted")
			var before: int = s.relation(q["giver"])["friendship"]
			var rivalry_before: int = s.relation(q["giver"])["rivalry"]
			var r := QuestBook.complete(s, q, 0 if q.get("options", []).size() > 0 else -1)
			check(r["ok"], id + " completed")
			check_eq(int(s.relation(q["giver"])["friendship"]), mini(100, before + 8), id + " friendship +8")
			check_eq(int(s.relation(q["giver"])["rivalry"]), rivalry_before, id + " leaves rivalry alone")
			check(s.relation(q["giver"])["memories"].has(id), id + " remembered")
			check(not QuestBook.complete(s, q, 0)["ok"], id + " cannot complete twice")
			check(not QuestBook.accept(s, id), id + " cannot restart")
			done += 1
	check_eq(done, 32, "all 32 episodes reachable and completed")
	check_eq(s.abilities_unlocked.size(), 8, "episodes unlock the 7 other abilities (8 in total)")
	check_eq(s.chips_balance, 16 * 15, "only the second episode of each resident pays (15 chips, content alpha)")


func test_friendship_and_rivalry_are_separate_axes() -> void:
	var s := _met_state()
	s.quests["npc_kyle.bond_02"] = QuestBook.COMPLETED
	var f0: int = s.relation("npc_kyle")["friendship"]
	talk(db, s, "npc_kyle", "card_room")
	check_eq(int(s.relation("npc_kyle")["rivalry"]), 10, "rivalry scene raises rivalry")
	check_eq(int(s.relation("npc_kyle")["friendship"]), f0, "friendship untouched by rivalry")
	check(s.get_flag("rivalry.kyle.scene_seen"), "rivalry scene seen once")
	talk(db, s, "npc_kyle", "card_room")
	check_eq(int(s.relation("npc_kyle")["rivalry"]), 10, "rivalry scene is not repeated")


func test_romance_is_opt_in_for_four_adults_and_can_end() -> void:
	var allowed := []
	for npc in db.npc_order:
		if db.npcs[npc].get("romance", false):
			allowed.append(npc)
	check_eq(allowed, ROMANCE, "romance only for Lumi, Kyle, Rira and Taeo")
	for e in db.dialogue:
		for eff in e.get("effects", []) + e.get("choices", []).reduce(func(a, c): return a + c.get("effects", []), []):
			if eff.get("type", "") == "romance":
				check(ROMANCE.has(eff["npc"]), "romance effect only for allowed residents (%s)" % e["id"])
	# Accept -> two dates -> decide together -> later end it kindly.
	var s := _met_state()
	s.quests["npc_rira.bond_02"] = QuestBook.COMPLETED
	# Romance is offered only to a close friend, and not on the same day as the second episode.
	s.relation("npc_rira")["friendship"] = 30
	s.set_flag("done:npc_rira.bond_02")
	s.day_count += 1
	s.time_of_day = "day"
	check_eq(talk(db, s, "npc_rira", "tea_house", ["더 알아가고"])[0], "rira.romance_offer", "offer after the second episode")
	check(s.relation("npc_rira")["romance"]["consent"], "consent given by choice")
	check_eq(talk(db, s, "npc_rira", "tea_house")[0], "rira.date1", "first date")
	check_eq(talk(db, s, "npc_rira", "tea_house")[0], "rira.date2", "second date")
	check_eq(talk(db, s, "npc_rira", "tea_house", ["함께"])[0], "rira.decide", "decision scene")
	check_eq(s.relation("npc_rira")["romance"]["stage"], "committed", "together")
	check_eq(talk(db, s, "npc_rira", "tea_house")[0], "rira_friend_gift", "a close friend's gift comes on another talk")
	check_eq(talk(db, s, "npc_rira", "tea_house")[0], "rira_memory", "the episode memory is still mentioned once")
	var f_before: int = s.relation("npc_rira")["friendship"]
	var shown := talk(db, s, "npc_rira", "tea_house", ["정리"])
	check_eq(shown[0], "rira.together", "together line with a way to end")
	check_eq(s.relation("npc_rira")["romance"]["stage"], "closed", "ended")
	check(not s.relation("npc_rira")["romance"]["consent"], "consent withdrawn")
	check_eq(int(s.relation("npc_rira")["friendship"]), f_before, "friendship kept after ending")
	# Declining keeps the friendship and never asks again.
	var d := _met_state()
	d.quests["npc_taeo.bond_02"] = QuestBook.COMPLETED
	d.relation("npc_taeo")["friendship"] = 30
	d.set_flag("done:npc_taeo.bond_02")
	d.day_count += 1
	var f0: int = d.relation("npc_taeo")["friendship"]
	check_eq(talk(db, d, "npc_taeo", "tailor", ["친구로"])[0], "taeo.romance_offer", "offer shown once")
	check_eq(d.relation("npc_taeo")["romance"]["stage"], "closed", "declined stays closed")
	check_eq(int(d.relation("npc_taeo")["friendship"]), f0, "declining costs nothing")
	check(not talk(db, d, "npc_taeo", "tailor")[0].begins_with("taeo.romance"), "no second offer")
	# Nobody else can be dated.
	var o := _met_state()
	o.quests["npc_ren.bond_02"] = QuestBook.COMPLETED
	check(not talk(db, o, "npc_ren", "market")[0].contains("romance"), "no romance with Ren")


func test_resident_pairs_change_only_through_events() -> void:
	check(db.edges.size() >= 8 and db.edges.size() <= 12, "8-12 registered pairs (%d)" % db.edges.size())
	var set_by := {}
	for id in db.quest_order:
		var q: Dictionary = db.quests[id]
		for eff in q.get("effects", []):
			if eff.get("type", "") == "edge":
				set_by[eff["pair"]] = id
	for e in db.dialogue:
		for c in e.get("choices", []):
			for eff in c.get("effects", []):
				if eff.get("type", "") == "edge":
					set_by[eff["pair"]] = e["id"]
	for pair in db.edges:
		check(set_by.has(pair), "pair %s changes through an event" % pair)
		var reacts := false
		for e in db.dialogue:
			reacts = reacts or e.get("conditions", {}).get("edge_phase", {}).has(pair) \
				or str(e.get("conditions", {})).contains(pair)
		check(reacts or pair == "lumi_kyle", "pair %s has a resident reaction" % pair)
	var s := _met_state()
	check_eq(s.edge_phase("moa_nora"), "neutral", "pairs start neutral")
	s.quests["npc_moa.bond_02"] = QuestBook.ACTIVE
	QuestBook.complete(s, db.quests["npc_moa.bond_02"], 1)
	check_eq(s.edge_phase("moa_nora"), "bonded", "episode bonds Moa and Nora")
	check_eq(talk(db, s, "npc_nora", "residential")[0], "nora_moa_edge", "Nora mentions it")


func test_residents_can_be_reached_next_to_objects() -> void:
	# Standing just below a resident must focus the resident, not a nearby object.
	for npc in db.npc_order:
		var def: Dictionary = db.npcs[npc]
		var places: Array = [def["schedule"]["day"], def["schedule"]["evening"]]
		places.append_array(def.get("overrides", []))
		for pl in places:
			var p := Geo.vec(pl["pos"])
			var stand := p + Vector2(0, 40)
			for it in db.locations[pl["loc"]].get("interactables", []):
				var d := Geo.vec(it["pos"]).distance_to(stand)
				check(d > 40.0 or d > float(it.get("radius", 60)), "%s at %s: %s is closer than the resident" % [npc, pl["loc"], it["id"]])
