extends "res://tests/test_case.gd"
## Content v0.3 Stage 4: house stages and room slots, 8 town projects with a real change each,
## 4 repeatable odd jobs, 16 one-time requests, 64 items in 6 categories (each obtainable),
## shops with unlocks and one-time trades. Money moves only through the ledger, once per key.

const HOME_LOCATIONS := ["player_home", "player_home_annex", "player_home_hall"]

var db := DataDB.new()
var errors: Array = db.load_all("res://data")


func _visible_slots(s: GameState) -> int:
	var n := 0
	for loc_id in HOME_LOCATIONS:
		for slot in db.locations[loc_id].get("slots", []):
			n += 1 if Conditions.check(slot.get("conditions", {}), s, loc_id) else 0
	return n


func _requests() -> Array:
	return db.quest_order.filter(func(id): return db.quests[id].get("kind", "quest") == "quest")


func test_house_has_three_expansions_with_more_slots() -> void:
	check_eq(errors, [], "data errors")
	var stages: Array = db.home["stages"]
	check_eq(stages.size(), 4, "starter + 3 expansions")
	var s := GameState.new()
	var expect := [3, 8, 16, 24]
	var last_cost := -1
	for st in stages:
		s.home_stage = int(st["stage"])
		check_eq(_visible_slots(s), expect[s.home_stage], "stage %d slots" % s.home_stage)
		check_eq(int(st["slots"]), expect[s.home_stage], "stage %d slot count in data" % s.home_stage)
		check(int(st["cost"]) > last_cost, "each expansion costs more")
		last_cost = int(st["cost"])
	# The annex and hall doors follow the stages.
	var home: Dictionary = db.locations["player_home"]
	for d in home["exits"] + home.get("buildings", []):
		if d.get("id", "") == "door_annex":
			s.home_stage = 1
			check(not Conditions.check(d["unlock"], s), "annex closed at stage 1")
			s.home_stage = 2
			check(Conditions.check(d["unlock"], s), "annex open at stage 2")


func test_house_upgrade_is_paid_once() -> void:
	var s := GameState.new()
	s.add_chips(200, "start")
	var st: Dictionary = db.home["stages"][1]
	var eff := [{"type": "spend", "amount": int(st["cost"]), "reason": "home:" + st["id"]}, {"type": "home_stage", "stage": 1}]
	check(Effects.apply(s, eff, "home:" + st["id"])["ok"], "upgrade paid")
	check(Effects.apply(s, eff, "home:" + st["id"]).get("skipped", false), "second upgrade with the same key is skipped")
	check_eq(s.chips_balance, 200 - int(st["cost"]), "paid once")
	var poor := GameState.new()
	poor.add_chips(10, "start")
	var r := Effects.apply(poor, eff, "home:" + st["id"])
	check(not r["ok"] and poor.home_stage == 0 and poor.chips_balance == 10, "not enough chips changes nothing")


func test_placement_rules() -> void:
	var s := GameState.new()
	s.grant_item("item.furniture.01_01", 2)
	check(s.place_item("slot_window", "item.furniture.01_01"), "place one stool")
	check(not s.place_item("slot_window", "item.furniture.01_01"), "slot already taken")
	check(s.place_item("slot_table", "item.furniture.01_01"), "second stool in another slot")
	check(not s.place_item("slot_bedside", "item.furniture.01_01"), "no stool left in storage")
	check(s.remove_placement("slot_window"), "back to storage")
	check_eq(s.owned_count("item.furniture.01_01"), 1, "storage count restored")
	check(s.collection.has("item.furniture.01_01"), "collection keeps the item")
	for cat in DataDB.EQUIP_CATEGORIES:
		for item in db.items.values():
			if item.get("category", "") == cat:
				check(not item.get("placeable", false), "%s is worn, not placed" % item["id"])


func test_eight_projects_each_change_the_world() -> void:
	check_eq(db.project_order.size(), 8, "8 projects")
	var world_text := JSON.stringify(db.locations) + JSON.stringify(db.npcs) + JSON.stringify(db.shops) + JSON.stringify(db.places)
	for pid in db.project_order:
		var p: Dictionary = db.projects[pid]
		check(world_text.contains('"%s"' % pid) or JSON.stringify(p.get("effects", [])).contains("town."), "%s changes something in the village" % pid)
		var reacts := false
		for e in db.dialogue:
			reacts = reacts or JSON.stringify(e.get("conditions", {})).contains(pid)
		check(reacts, "%s has a resident reaction" % pid)
	var s := GameState.new()
	s.add_chips(1000, "start")
	s.set_flag("story.act1_started")
	var p: Dictionary = db.projects["board_restoration"]
	var eff := [{"type": "spend", "amount": int(p["cost"]), "reason": "project:board_restoration"}, {"type": "project", "project": "board_restoration"}]
	eff.append_array(p["effects"])
	check(Effects.apply(s, eff, "project:board_restoration")["ok"], "funded")
	Effects.apply(s, eff, "project:board_restoration")
	check_eq(s.chips_balance, 1000 - int(p["cost"]), "funded once")
	check_eq(s.owned_count("item.decor.01_03"), 1, "project gift once")


func test_four_jobs_repeatable_and_paid_on_completion() -> void:
	check_eq(db.jobs.size(), 4, "4 odd jobs")
	var types := {}
	for jid in db.jobs:
		types[db.jobs[jid]["type"]] = true
	check_eq(types.size(), 3, "collect, deliver and shelve")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var s := GameState.new()
	# Letter delivery: only the right resident, paid once.
	var post := PlazaJob.create(db.jobs["job.post_delivery"], rng, 1)
	var wrong := "npc_lumi" if post.recipient != "npc_lumi" else "npc_sera"
	check(not post.deliver(s, wrong)["ok"], "wrong recipient refused")
	check(post.deliver(s, post.recipient)["done"], "delivered")
	check(not post.deliver(s, post.recipient)["ok"], "no second pay")
	check_eq(s.chips_balance, 12, "letter pays 12")
	# Shelving: wrong good changes nothing.
	var shelf := PlazaJob.create(db.jobs["job.shop_shelving"], rng, 2)
	var need := shelf.next_shelf_good()
	var other := "리본" if need != "리본" else "찻잔"
	check(shelf.shelve(s, other).get("wrong", false), "wrong good")
	for i in 3:
		shelf.shelve(s, shelf.next_shelf_good())
	check(shelf.rewarded, "shelving done")
	# Lantern check: three spots in the grove.
	var lantern := PlazaJob.create(db.jobs["job.lantern_check"], rng, 3)
	for spot in lantern.remaining():
		lantern.collect(s, spot)
	check_eq(s.chips_balance, 12 + 10 + 12, "all three jobs paid exactly once")
	check_eq(s.jobs_completed, 3, "three runs counted")
	var reasons: Array = s.chips_ledger.map(func(e): return e["reason"])
	check_eq(reasons, ["job:job.post_delivery:1", "job:job.shop_shelving:2", "job:job.lantern_check:3"], "ledger reasons carry the run")


func test_sixteen_requests_once_each() -> void:
	check_eq(_requests().size(), 16, "16 requests")
	var s := GameState.new()
	for f in ["story.act1_started", "story.act1_complete", "story.act2_started", "story.act3_started"]:
		s.set_flag(f)
	s.projects["board_restoration"] = "complete"
	s.projects["guest_cottage"] = "complete"
	var total := 0
	for id in _requests():
		var q: Dictionary = db.quests[id]
		check(q["giver"] != q["target"], id + " sends you to someone else")
		check(db.npcs.has(q["target"]), id + " target is a resident")
		check(int(q["reward"]) > 0, id + " pays chips")
		check(Conditions.check(q.get("unlock", {}), s), id + " can unlock")
		QuestBook.accept(s, id)
		QuestBook.complete(s, q)
		check(not QuestBook.complete(s, q)["ok"], id + " pays once")
		total += int(q["reward"])
	check_eq(s.chips_balance, total, "rewards sum")
	check_eq(s.contributions.size(), 16, "requests done during act 3 count for the festival once each")


func test_sixty_four_items_in_six_categories_each_obtainable() -> void:
	var per := {}
	var new_items := 0
	for id in db.item_order:
		var item: Dictionary = db.items[id]
		check(DataDB.ITEM_CATEGORIES.has(item.get("category", "")), id + " category")
		if str(id).begins_with("item."):
			new_items += 1
			per[item["category"]] = int(per.get(item["category"], 0)) + 1
	check_eq(new_items, 64, "64 new items")
	check_eq(per.size(), 6, "6 categories")
	for c in per:
		check(int(per[c]) >= 8, "%s has 8 or more" % c)
	var sources := {}
	for shop in db.shops.values():
		for e in shop["items"]:
			sources[e if e is String else e["item"]] = "shop"
	for t in db.trades:
		sources[t["get"]] = "trade"
	sources[str(db.poker["modes"]["tournament"]["reward_item"])] = "tournament"
	var effect_text := JSON.stringify(db.dialogue) + JSON.stringify(db.projects) + JSON.stringify(db.quests)
	for id in db.item_order:
		if not sources.has(id) and effect_text.contains('"%s"' % id):
			sources[id] = "event"
		check(sources.has(id), id + " can be obtained")


func test_shop_unlocks_and_trades() -> void:
	var s := GameState.new()
	var open_now := func(shop_id: String) -> Array:
		var out: Array = []
		for e in db.shops[shop_id]["items"]:
			if e is String or Conditions.check(e.get("unlock", {}), s):
				out.append(e if e is String else e["item"])
		return out
	var first: Array = open_now.call("sera_shop")
	check(first.has("furniture.lamp_small"), "lamp always on sale")
	check(not first.has("item.furniture.04_01"), "later furniture locked")
	s.projects["board_restoration"] = "complete"
	check(open_now.call("sera_shop").has("item.furniture.04_01"), "unlocked by the board project")
	check(not JSON.stringify(db.shops["swap_shop"]).contains("item.card_back.08_06"), "tournament card back is not sold")
	for t in db.trades:
		check(int(t.get("give_count", 1)) >= 2, "%s trades duplicates" % t["id"])
		check(t["give"] != t["get"], "%s gives something new" % t["id"])
