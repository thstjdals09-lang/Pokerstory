extends "res://tests/test_case.gd"
## Checks the shipped data files and the dialogue/goal conditions they drive.

const LAMP := "furniture.lamp_small"

var db := DataDB.new()
var errors: Array = db.load_all("res://data")


func _entry(npc: String, location: String, s: GameState) -> String:
	return DialogueResolver.resolve(db.dialogue, npc, location, s).get("id", "")


func test_data_loads_without_errors() -> void:
	check_eq(errors, [], "data errors")


func test_spec_values() -> void:
	var econ: Dictionary = db.poker["economy"]
	check_eq(int(econ["entry_fee"]), 0, "entry fee 0")
	check_eq(int(econ["reward_win"]), 60, "win 60")
	check_eq(int(econ["reward_draw"]), 30, "draw 30")
	check_eq(int(econ["reward_lose"]), 20, "lose 20")
	check_eq(int(econ["first_play_bonus"]), 40, "bonus 40")
	check_eq(db.item_price(LAMP), 50, "lamp 50")
	check_eq(int(db.poker["rules"]["max_discards"]), 3, "max 3 discards")
	for id in ["npc_lumi", "npc_moa", "npc_sera"]:
		check(db.npcs.has(id), "npc " + id)
	for id in ["village_square", "player_home", "card_room", "small_shop"]:
		check(db.locations.has(id), "location " + id)


func test_lumi_dialogue_progression() -> void:
	var s := GameState.new()
	check_eq(_entry("npc_lumi", "village_square", s), "lumi_intro", "first meeting")
	check_eq(_entry("npc_lumi", "card_room", s), "lumi_intro_cardroom", "met first at the card room")
	s.set_flag("intro_met_lumi")
	check_eq(_entry("npc_lumi", "village_square", s), "lumi_before_poker", "repeat before poker differs")
	s.poker_hands_completed = 1
	check_eq(_entry("npc_lumi", "village_square", s), "lumi_default", "after poker")
	s.grant_item(LAMP)
	check_eq(_entry("npc_lumi", "village_square", s), "lumi_lamp_not_placed", "bought but not placed")
	s.place_item("slot_window", LAMP)
	check_eq(_entry("npc_lumi", "village_square", s), "lumi_lamp_reaction", "reacts to placed lamp")
	check_eq(_entry("npc_lumi", "card_room", s), "lumi_lamp_reaction_cardroom", "reacts in card room too")
	s.set_flag("lumi_lamp_reaction_seen")
	check_eq(_entry("npc_lumi", "village_square", s), "lumi_after_lamp", "follow-up after reaction")


func test_goal_progression() -> void:
	var s := GameState.new()
	var goal := func() -> String:
		for g in db.goals:
			if Conditions.check(g["conditions"], s, "village_square"):
				return g["text"]
		return ""
	check(goal.call().contains("루미에게 인사"), "goal 1")
	s.set_flag("intro_met_lumi")
	check(goal.call().contains("포커 모임"), "goal 2")
	s.poker_hands_completed = 1
	check(goal.call().contains("등불 사기"), "goal 3")
	s.grant_item(LAMP)
	check(goal.call().contains("배치"), "goal 4")
	s.place_item("slot_window", LAMP)
	check(goal.call().contains("다시 말 걸기"), "goal 5")
	s.set_flag("lumi_lamp_reaction_seen")
	check(goal.call().contains("자유롭게"), "goal 6")


func test_format_line() -> void:
	check_eq(DialogueResolver.format_line("안녕 {player}! {n}칩", {"player": "루", "n": 5}), "안녕 루! 5칩", "placeholders")
