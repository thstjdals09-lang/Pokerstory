extends "res://tests/test_case.gd"
## One-time quest, repeatable odd job, time-of-day placement, and the v1 -> v2 save migration.

const QUEST := "quest.sera_delivery"
const PATH := "user://unit_test_migration.json"

var db := DataDB.new()
var errors: Array = db.load_all("res://data")


func _job_run(seed_value: int) -> PlazaJob:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return PlazaJob.create(db.jobs["job.plaza_cleanup"], rng)


func test_quest_pays_once() -> void:
	var s := GameState.new()
	var quest: Dictionary = db.quests[QUEST]
	check_eq(int(quest["reward"]), 30, "approved reward 30")
	check(not QuestBook.complete(s, quest)["ok"], "cannot complete before accepting")
	check(QuestBook.accept(s, QUEST), "accept")
	check(not QuestBook.accept(s, QUEST), "cannot accept twice")
	var r := QuestBook.complete(s, quest)
	check(r["ok"] and int(r["reward"]) == 30, "complete pays 30")
	check_eq(s.chips_balance, 30, "balance")
	check(not QuestBook.complete(s, quest)["ok"], "second completion rejected")
	check(not QuestBook.accept(s, QUEST), "completed quest cannot restart")
	check_eq(s.chips_balance, 30, "still 30")
	var reloaded := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check_eq(QuestBook.state_of(reloaded, QUEST), "completed", "state survives save")
	check(not QuestBook.complete(reloaded, quest)["ok"], "no reward after reload")


func test_job_pays_only_after_every_spot() -> void:
	var s := GameState.new()
	var run := _job_run(7)
	check_eq(run.total(), 3, "three spots (Design Review 03, D5)")
	var ids: Array = run.spots.keys()
	var first: String = ids[0]
	check(run.collect(s, first)["ok"], "first pickup")
	for i in 20:
		check(not run.collect(s, first)["ok"], "same spot cannot be collected again")
	check(not run.collect(s, "spot_999")["ok"], "unknown spot rejected")
	check_eq(s.chips_balance, 0, "no pay before completion")
	for i in range(1, ids.size() - 1):
		run.collect(s, ids[i])
	check_eq(s.chips_balance, 0, "still no pay with one left")
	var last := run.collect(s, ids[ids.size() - 1])
	check(last["done"], "done after the last spot")
	check_eq(int(last["reward"]), 10, "approved reward 10")
	check_eq(s.chips_balance, 10, "paid 10")
	check(not run.collect(s, ids[0])["ok"], "finished run pays nothing more")
	check_eq(s.chips_ledger.size(), 1, "one ledger entry")
	check_eq(s.chips_ledger[0]["reason"], "job:job.plaza_cleanup", "ledger reason")


func test_job_is_repeatable_from_zero_chips() -> void:
	var s := GameState.new()
	for n in 2:
		var run := _job_run(n + 1)
		for id in run.spots.keys():
			run.collect(s, id)
	check_eq(s.chips_balance, 20, "two runs from zero reach the 20-chip stake")
	check_eq(s.jobs_completed, 2, "runs counted")
	check(PokerEconomy.can_join(s, db.poker["economy"]), "can join poker again")


func test_job_spots_are_spread_out() -> void:
	var run := _job_run(3)
	var ids: Array = run.spots.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var d: float = run.spots[ids[i]]["pos"].distance_to(run.spots[ids[j]]["pos"])
			check(d > 68.0, "spots %s and %s are %.0f apart (> 2x pickup radius)" % [ids[i], ids[j], d])


func test_each_resident_is_in_one_place_per_time() -> void:
	check_eq(errors, [], "data errors")
	for npc_id in db.npcs:
		for t in ["day", "evening"]:
			check(db.npc_locations(npc_id, t).size() <= 1, "%s at %s" % [npc_id, t])
	check_eq(db.npc_locations("npc_lumi", "day"), ["village_square"], "Lumi by day")
	check_eq(db.npc_locations("npc_lumi", "evening"), ["card_room"], "Lumi by evening")


func test_card_room_requires_evening() -> void:
	var door: Dictionary = {}
	for b in db.locations["village_square"]["buildings"]:
		if b["target"] == "card_room":
			door = b
	check_eq(door.get("requires_time", ""), "evening", "card room opens in the evening")


func test_time_conditions() -> void:
	var s := GameState.new()
	check(Conditions.check({"time": "day"}, s), "starts in the day")
	s.time_of_day = "evening"
	check(Conditions.check({"time": "evening"}, s), "evening")
	check(not Conditions.check({"time": "day"}, s), "not day")


func test_v1_save_migrates_without_touching_chips() -> void:
	var v1 := {
		"save_version": 1, "player_name": "옛날", "chips_balance": 60,
		"chips_ledger": [{"seq": 1, "delta": 60, "reason": "poker_lose", "balance": 60}],
		"flags": {"intro_met_lumi": true, "first_poker_bonus_claimed": true},
		"poker_hands_completed": 1, "poker_record": {"win": 0, "draw": 0, "lose": 1},
		"owned_items": {}, "collection": [], "home_placements": [],
		"current_scene": "card_room", "player_position": [480, 560],
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(v1))
	f.close()
	var r := SaveSystem.load_state(PATH)
	check(r["ok"], "v1 loads")
	var s: GameState = r["state"]
	check_eq(s.chips_balance, 60, "old balance kept (no reset to 100)")
	check_eq(s.time_of_day, "evening", "saved in the card room -> evening")
	check_eq(s.quests, {}, "no quests yet")
	check_eq(s.pending_poker_stake, 0, "nothing pending")
	check_eq(s.poker_in_progress, {}, "no saved hand")
	check_eq(s.to_dict()["save_version"], 3, "written back as v3")
	SaveSystem.delete(PATH)


func test_saved_hand_that_cannot_restore_is_reported_not_refunded() -> void:
	var s := GameState.new()
	s.add_chips(40, "start")
	PokerEconomy.place_stake(s, {"stake": 20})
	var hand := PokerMatch.new(Deck.shuffled(8)).to_dict()
	hand["deck"] = hand["deck"].slice(0, 10)
	s.poker_in_progress = hand
	SaveSystem.save(s, PATH)
	var r := SaveSystem.load_state(PATH)
	check(not r["ok"], "damaged hand is not loaded")
	check_eq(r["error"], "corrupt", "reported as damaged")
	SaveSystem.delete(PATH)


func test_goals_follow_the_loop() -> void:
	var s := GameState.new()
	s.add_chips(40, "start")
	var goal := func() -> String:
		for g in db.goals:
			if Conditions.check(g["conditions"], s, "village_square"):
				return g["text"]
		return ""
	check(goal.call().contains("루미에게 인사"), "goal: greet")
	s.set_flag("intro_met_lumi")
	var g: String = goal.call()
	check(g.contains("아르바이트") and g.contains("부탁") and g.contains("포커"), "goal: every chip source, poker optional (%s)" % g)
	s.add_chips(10, "job")
	check(goal.call().contains("잡화점에서 작은 등불 사기"), "goal: buy the lamp at 50 chips")
	s.quests[QUEST] = "active"
	check(goal.call().contains("꾸러미"), "goal: delivery while quest active")
	s.quests[QUEST] = "completed"
	s.chips_balance = 0
	check(goal.call().contains("아르바이트"), "goal: odd job when broke")
