extends "res://tests/test_case.gd"
## Content v0.3.1: "change + save" is one unit. A failed save puts the state back exactly; the same
## action done again after a successful save is applied once.

var db := DataDB.new()
var errors: Array = db.load_all("res://data")


func _state() -> GameState:
	var s := GameState.new()
	s.add_chips(300, "starting_chips")
	s.set_flag("story.act1_started")
	for npc in db.npc_order:
		s.relation(npc)["met"] = true
	return s


func _snap(s: GameState) -> String:
	return JSON.stringify(s.to_dict())


## Runs `change` with a failing save (must roll back), then with a working save (applies once),
## then again (the one-time part must not repeat when `once` is true).
func _fail_then_succeed(label: String, s: GameState, change: Callable, once: bool = true) -> void:
	var before := _snap(s)
	var failed := StateTransaction.run(s, change, func(): return false)
	check_eq(failed.get("reason", ""), "save_failed", label + ": reported")
	check_eq(_snap(s), before, label + ": state exactly as before")
	var ok := StateTransaction.run(s, change, func(): return true)
	check(ok["ok"], label + ": works after a good save")
	var after := _snap(s)
	check(after != before, label + ": changed once")
	if once:
		StateTransaction.run(s, change, func(): return true)
		check_eq(_snap(s), after, label + ": not applied a second time")


func test_restore_keeps_the_same_object() -> void:
	var s := _state()
	var ref := s
	var before := s.to_dict()
	s.add_chips(50, "x")
	s.grant_item("item.decor.01_03")
	s.projects["board_restoration"] = "complete"
	s.restore(before)
	check(ref == s, "same object")
	check_eq(s.chips_balance, 300, "chips back")
	check_eq(s.owned_count("item.decor.01_03"), 0, "item back")
	check(not s.project_done("board_restoration"), "project back")
	check_eq(s.chips_ledger.size(), 1, "ledger back")


func test_representative_changes_roll_back() -> void:
	var s := _state()
	# purchase
	_fail_then_succeed("purchase", s, func(): return {"ok": s.owned_count("furniture.lamp_small") == 0 and s.purchase("furniture.lamp_small", 50)})
	# placement and storage
	_fail_then_succeed("place", s, func(): return {"ok": s.place_item("slot_window", "furniture.lamp_small")})
	_fail_then_succeed("store", s, func(): return {"ok": s.remove_placement("slot_window")})
	# project funding (spend + project + gift, keyed)
	var p: Dictionary = db.projects["board_restoration"]
	var eff: Array = [{"type": "spend", "amount": int(p["cost"]), "reason": "project:board_restoration"}, {"type": "project", "project": "board_restoration"}]
	eff.append_array(p["effects"])
	_fail_then_succeed("project", s, func(): return Effects.apply(s, eff, "project:board_restoration"))
	check_eq(s.owned_count("item.decor.01_03"), 1, "project gift exactly once")
	# house expansion
	var st: Dictionary = db.home["stages"][1]
	var home := [{"type": "spend", "amount": int(st["cost"]), "reason": "home:" + st["id"]}, {"type": "home_stage", "stage": 1}]
	_fail_then_succeed("house", s, func(): return Effects.apply(s, home, "home:" + st["id"]))
	# request with reward
	QuestBook.accept(s, "quest.rira_tea")
	_fail_then_succeed("request", s, func(): return QuestBook.complete(s, db.quests["quest.rira_tea"]))
	check_eq(s.chips_ledger.filter(func(e): return e["reason"] == "quest:quest.rira_tea").size(), 1, "request paid once")
	# one-time event reward (a memento through a keyed choice)
	_fail_then_succeed("event", s, func(): return Effects.apply(s, [{"type": "item", "item": "item.memento.08_08"}, {"type": "friendship", "npc": "npc_ona", "amount": 3}], "dlg:evt_sky_lantern"))
	check_eq(s.owned_count("item.memento.08_08"), 1, "memento once")
	# odd job: the last pickup pays
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var run := PlazaJob.create(db.jobs["job.plaza_cleanup"], rng, 1)
	var spots := run.remaining()
	run.collect(s, spots[0])
	run.collect(s, spots[1])
	var before_job := _snap(s)
	var collected := run.collected.duplicate()
	var r := StateTransaction.run(s, func(): return run.collect(s, spots[2]), func(): return false)
	check_eq(r.get("reason", ""), "save_failed", "job: reported")
	check_eq(_snap(s), before_job, "job: no pay, count unchanged")
	run.collected = collected
	run.rewarded = false
	check(StateTransaction.run(s, func(): return run.collect(s, spots[2]), func(): return true)["done"], "job: finished on retry")
	check_eq(s.chips_ledger.filter(func(e): return str(e["reason"]).begins_with("job:")).size(), 1, "job paid once")


func test_poker_stake_and_settlement_roll_back() -> void:
	var s := _state()
	var econ: Dictionary = db.poker["economy"]
	var before := _snap(s)
	var r := StateTransaction.run(s, func(): return {"ok": PokerEconomy.place_stake(s, econ)}, func(): return false)
	check_eq(r["reason"], "save_failed", "stake reported")
	check_eq(_snap(s), before, "no stake taken")
	check(StateTransaction.run(s, func(): return {"ok": PokerEconomy.place_stake(s, econ)}, func(): return true)["ok"], "stake on retry")
	check_eq(s.chips_balance, 280, "one stake")
	var deck := ["AS", "QS", "AH", "QH", "KD", "9D", "7C", "5C", "2S", "3H", "6H", "4D", "8S", "JC"]
	var m := PokerMatch.new(Deck.stacked(deck))
	m.player_draw([])
	var settle := func(): return PokerEconomy.settle(s, m, econ)
	var mid := _snap(s)
	check_eq(StateTransaction.run(s, settle, func(): return false)["reason"], "save_failed", "settle reported")
	check_eq(_snap(s), mid, "nothing paid")
	m.settled = false  # Game's undo for the hand object
	var ok := StateTransaction.run(s, settle, func(): return true)
	check(ok["ok"], "settled on retry")
	check_eq(s.chips_balance, 320, "paid once: 280 + 40")
	check(not StateTransaction.run(s, settle, func(): return true)["ok"], "cannot settle twice")
