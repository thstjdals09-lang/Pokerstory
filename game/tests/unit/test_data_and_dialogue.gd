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
	# Economy v0.2.1 (approved)
	var econ: Dictionary = db.poker["economy"]
	check_eq(int(econ["starting_chips"]), 100, "start 100")
	check_eq(int(econ["stake"]), 20, "stake 20")
	check_eq(int(econ["payout_win"]), 40, "win returns 40")
	check_eq(int(econ["payout_draw"]), 20, "draw returns 20")
	check_eq(int(econ["payout_lose"]), 0, "loss returns 0")
	check(not econ.has("first_play_bonus") and not econ.has("reward_lose"), "no bonus, no loss reward")
	check_eq(db.item_price(LAMP), 50, "lamp 50")
	check_eq(int(db.jobs["job.plaza_cleanup"]["reward"]), 10, "job 10")
	check_eq(int(db.quests["quest.sera_delivery"]["reward"]), 30, "quest 30")
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


func test_quest_dialogue_progression() -> void:
	var s := GameState.new()
	s.set_flag("intro_met_lumi")
	check_eq(_entry("npc_sera", "small_shop", s), "sera_first", "Sera greets")
	s.set_flag("sera_met")
	check_eq(_entry("npc_sera", "small_shop", s), "sera_default", "Sera repeat")
	s.quests["quest.sera_delivery"] = "active"
	check_eq(_entry("npc_sera", "small_shop", s), "sera_quest_active", "Sera reminds")
	check_eq(_entry("npc_lumi", "village_square", s), "lumi_quest_delivery", "Lumi receives by day")
	check_eq(_entry("npc_lumi", "card_room", s), "lumi_quest_delivery", "Lumi receives by evening")
	s.quests["quest.sera_delivery"] = "completed"
	check(_entry("npc_lumi", "village_square", s) != "lumi_quest_delivery", "no delivery after completion")
	check_eq(_entry("npc_sera", "small_shop", s), "sera_quest_done", "Sera thanks once")
	s.set_flag("sera_quest_thanked")
	check_eq(_entry("npc_sera", "small_shop", s), "sera_default", "then back to default")
	var offer_choice: Dictionary = DialogueResolver.find(db.dialogue, "sera_default")["choices"][1]
	check(not Conditions.check(offer_choice["conditions"], s), "offer choice hidden after completion")


func test_format_line() -> void:
	check_eq(DialogueResolver.format_line("안녕 {player}! {n}칩", {"player": "루", "n": 5}), "안녕 루! 5칩", "placeholders")
