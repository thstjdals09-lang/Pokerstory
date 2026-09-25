extends "res://tests/test_case.gd"
## Content v0.3 Stage 6 (06_integration/06_CONTENT_AUDIT, 01 "12 reactions"): unique ids and
## references, the 12 cross-system reactions, rewards applied once, the story reachable through
## every branch without poker, and romance only with consent.

var db := DataDB.new()
var errors: Array = db.load_all("res://data")


func _met_state() -> GameState:
	var s := GameState.new()
	for npc in db.npc_order:
		s.relation(npc)["met"] = true
	for f in ["intro_met_lumi", "moa_met", "sera_met", "sera_quest_thanked", "lumi_lamp_reaction_seen", "sera_lamp_reaction_seen", "story.prologue_complete"]:
		s.set_flag(f)
	return s


## Talks until `want` shows (one-time lines may come first); returns true when it did.
func _reaches(s: GameState, npc: String, loc: String, want: String) -> bool:
	for i in 6:
		var shown := talk(db, s, npc, loc)
		if shown.has(want):
			return true
		if shown.is_empty():
			return false
	return false


func test_ids_are_unique_and_references_exist() -> void:
	check_eq(errors, [], "validator finds no broken reference")
	var seen := {}
	for e in db.dialogue:
		check(not seen.has(e["id"]), "dialogue id %s unique" % e["id"])
		seen[e["id"]] = true
	var world_ids := {}
	for loc_id in db.locations:
		for group in ["interactables", "buildings", "gates", "exits"]:
			for it in db.locations[loc_id].get(group, []):
				if it.has("id"):
					check(not world_ids.has(it["id"]), "world object %s unique (%s and %s)" % [it["id"], world_ids.get(it["id"], ""), loc_id])
					world_ids[it["id"]] = loc_id
	var items := {}
	for id in db.item_order:
		check(not items.has(id), "item %s unique" % id)
		items[id] = true
	for id in db.quest_order:
		check(db.quests.has(id), "quest %s registered" % id)
	check_eq(db.quest_order.size(), 48, "16 requests + 32 episodes, no duplicates")


func test_twelve_cross_system_reactions() -> void:
	# 1. lamp placed -> Lumi
	var s := GameState.new()
	s.set_flag("intro_met_lumi")
	s.grant_item("furniture.lamp_small")
	s.place_item("slot_window", "furniture.lamp_small")
	check(_reaches(s, "npc_lumi", "village_square", "lumi_lamp_reaction"), "1 lamp -> Lumi")
	# 2. parcel delivered -> Sera thanks and Lumi's thanks
	s = GameState.new()
	s.set_flag("sera_met")
	s.quests["quest.sera_delivery"] = QuestBook.COMPLETED
	check(_reaches(s, "npc_sera", "small_shop", "sera_quest_done"), "2 parcel -> Sera")
	check(db.quests["quest.sera_delivery"]["complete_dialogue"] == "lumi_quest_thanks", "2 parcel -> Lumi")
	# 3. plaza job -> Miri
	s = _met_state()
	s.jobs_completed = 1
	check(_reaches(s, "npc_miri", "community_hall", "miri_cleanup_praise"), "3 job -> Miri")
	# 4. three hands with Lumi -> rivalry scene (no win needed)
	s = _met_state()
	s.relation("npc_lumi")["poker_hands"] = 3
	check(_reaches(s, "npc_lumi", "village_square", "lumi_rivalry"), "4 poker x3 -> Lumi rivalry")
	# 5. heard Kyle -> Lumi changes how she runs the gathering
	s = _met_state()
	for f in ["story.act1_complete", "story.act2_started", "story.act2_heard_lumi", "story.act2_heard_kyle"]:
		s.set_flag(f)
	check(_reaches(s, "npc_lumi", "village_square", "lumi_after_kyle"), "5 Kyle -> Lumi")
	# 6. postbox garden -> Nora and Moa move and talk
	s = _met_state()
	s.set_flag("story.act1_complete")
	s.projects["postbox_garden"] = "complete"
	check_eq(Geo.vec(db.npc_place("npc_nora", "day", s)["pos"]), Vector2(640, 300), "6 Nora by the garden")
	check_eq(db.npc_place("npc_moa", "day", s)["loc"], "residential", "6 Moa visits the garden")
	check(_reaches(s, "npc_moa", "residential", "moa_town") and _reaches(s, "npc_nora", "residential", "nora_town"), "6 garden lines")
	# 7. workshop opens -> Sera's stock line and Bibi
	s = _met_state()
	s.projects["board_restoration"] = "complete"
	check(_reaches(s, "npc_sera", "small_shop", "sera_town") and _reaches(s, "npc_bibi", "workshop", "bibi_town"), "7 workshop")
	check_eq(db.npc_place("npc_bibi", "day", s)["loc"], "workshop", "7 Bibi inside")
	# 8. lantern path -> Haru and Ona
	s = _met_state()
	s.projects["lantern_path"] = "complete"
	check(_reaches(s, "npc_haru", "waterfront", "haru_town") and _reaches(s, "npc_ona", "grove", "ona_town"), "8 lantern path")
	# 9. house expansion -> Yul visits
	s = _met_state()
	s.home_stage = 2
	check(_reaches(s, "npc_yul", "residential", "yul_home_visit"), "9 house -> Yul")
	# 10. tea-house social game -> Rira and Taeo bond
	s = _met_state()
	s.set_flag("tea.social_played")
	check(_reaches(s, "npc_rira", "tea_house", "rira_tea_social"), "10 tea social -> Rira")
	check_eq(s.edge_phase("rira_taeo"), "bonded", "10 pair bonded")
	check(_reaches(s, "npc_taeo", "tailor", "taeo_rira_edge"), "10 Taeo notices")
	# 11. first festival -> Juno, Miri, Kyle, Lumi
	s = _met_state()
	s.set_flag("story.act3_complete")
	s.set_flag("story.postgame")
	for pair in [["npc_juno", "village_square"], ["npc_miri", "community_hall"], ["npc_kyle", "grove"], ["npc_lumi", "village_square"]]:
		check(_reaches(s, pair[0], pair[1], pair[0].trim_prefix("npc_") + "_festival"), "11 festival -> " + pair[0])
	# 12. festival without poker -> Moa
	s = _met_state()
	s.set_flag("story.act3_complete")
	check(_reaches(s, "npc_moa", "village_square", "moa_no_poker_festival"), "12 no-poker festival -> Moa")


func test_repeating_an_event_never_pays_twice() -> void:
	# Every one-time dialogue entry and keyed choice applied twice changes the state once.
	var once_entries := 0
	for e in db.dialogue:
		var keyed: Array = []
		if e.get("once", false) and not e.get("effects", []).is_empty():
			keyed.append([e.get("effects", []), DialogueResolver.once_key(e)])
		for c in e.get("choices", []):
			if c.has("once_key") and not c.get("effects", []).is_empty():
				keyed.append([c["effects"], str(c["once_key"])])
		for k in keyed:
			var s := _met_state()
			s.add_chips(500, "start")
			Effects.apply(s, k[0], k[1])
			var snap := JSON.stringify(s.to_dict())
			Effects.apply(s, k[0], k[1])
			check_eq(JSON.stringify(s.to_dict()), snap, "%s applies once" % e["id"])
			once_entries += 1
	check(once_entries >= 10, "keyed events checked (%d)" % once_entries)
	# The festival helper memento: first festival and later festivals share one key.
	var s := _met_state()
	var first: Array = []
	var again: Dictionary = {}
	for e in db.dialogue:
		for c in e.get("choices", []):
			if JSON.stringify(c.get("effects", [])).contains("item.memento.04_08"):
				if e["id"] == "festival_booth_again":
					again = c
				else:
					first = c["effects"]
	Effects.apply(s, first)
	Effects.apply(s, again["effects"], again["once_key"])
	Effects.apply(s, again["effects"], again["once_key"])
	check_eq(s.owned_count("item.memento.04_08"), 1, "helper memento only once across festivals")


func test_story_completes_on_every_branch_without_poker() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 606
	for run in 40:
		var s := _met_state()
		s.relation("npc_kyle")["met"] = true
		var pick := func(options: Array) -> String: return options[rng.randi_range(0, options.size() - 1)]
		talk(db, s, "npc_moa", "village_square", ["찾아볼게요"])
		var clues: Array = [["obj:postbox_stamp_spot", "residential"], ["obj:grove_sign_west", "grove"], ["obj:grove_sign_east", "grove"]]
		if rng.randi() % 2 == 0:
			clues.reverse()
		for c in clues:
			talk(db, s, c[0], c[1])
		talk(db, s, "obj:card_room_board", "village_square", [pick.call(["친구와", "포커를 몰라도"])])
		var views: Array = [["npc_lumi", "village_square"], ["npc_kyle", "card_room"]]
		if rng.randi() % 2 == 0:
			views.reverse()
		for v in views:
			talk(db, s, v[0], v[1])
		if rng.randi() % 2 == 0:
			talk(db, s, "npc_rira", "tea_house", ["찻집 모임"])
			for i in 3:
				talk(db, s, "obj:tea_chair_%d" % (i + 1), "tea_house")
			talk(db, s, "npc_rira", "tea_house")
		else:
			talk(db, s, "npc_kyle", "grove", ["규칙판"])
			for i in 3:
				talk(db, s, "obj:rules_board", "grove")
			talk(db, s, "npc_kyle", "grove")
		check(s.get_flag("story.act2_prep_done"), "run %d: preparation done" % run)
		var who: String = pick.call(["npc_lumi", "npc_kyle"])
		talk(db, s, who, "waterfront", [pick.call(["친목", "규칙 설명", "둘 다"])])
		check(s.get_flag("story.act3_started"), "run %d: act 3 reached" % run)
		var sources: Array = ["juno", "moa", "letters", "lights"]
		for i in sources.size():
			var j := rng.randi_range(i, sources.size() - 1)
			var t = sources[i]
			sources[i] = sources[j]
			sources[j] = t
		for src in sources.slice(0, 3):
			match src:
				"juno":
					talk(db, s, "npc_juno", "village_square", ["장식"])
				"moa":
					talk(db, s, "npc_moa", "village_square", ["관전"])
				"letters", "lights":
					var q: String = "quest.festival_" + str(src)
					QuestBook.accept(s, q)
					QuestBook.complete(s, db.quests[q])
		talk(db, s, "obj:hall_meeting", "community_hall", [pick.call(["하트", "클로버", "다이아", "스페이드"])])
		s.time_of_day = "evening"
		talk(db, s, "obj:festival_booth", "village_square", [pick.call(["관전", "정리", "인사"])])
		check(s.get_flag("story.act3_complete"), "run %d: festival ends" % run)
		s.time_of_day = "day"
		talk(db, s, "npc_lumi", "village_square")
		check(s.get_flag("story.postgame"), "run %d: postgame" % run)
		check_eq(s.poker_hands_completed, 0, "run %d: no poker" % run)


func test_romance_needs_consent() -> void:
	for e in db.dialogue:
		var id: String = e["id"]
		if id.contains(".date") or id.ends_with(".decide"):
			var c: Dictionary = e.get("conditions", {})
			check(c.has("romance_stage"), id + " requires a romance stage")
			if id.ends_with(".date1"):
				check(c.get("romance_consent", {}).values().has(true), id + " requires consent")
	for npc in ["npc_lumi", "npc_kyle", "npc_rira", "npc_taeo"]:
		var offer := DialogueResolver.find(db.dialogue, npc.trim_prefix("npc_") + ".romance_offer")
		var said_no := false
		for c in offer.get("choices", []):
			said_no = said_no or c.get("effects", []).is_empty()
		check(said_no, npc + " offer can be declined without effects")
