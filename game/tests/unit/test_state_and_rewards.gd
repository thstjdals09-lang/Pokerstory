extends "res://tests/test_case.gd"

const ECONOMY := {
	"starting_chips": 0, "entry_fee": 0,
	"reward_win": 60, "reward_draw": 30, "reward_lose": 20, "first_play_bonus": 40,
}
const LAMP := "furniture.lamp_small"


func _finished_match(outcome: String) -> PokerMatch:
	var order := {
		"win": ["AS", "QS", "AH", "QH", "KD", "9D", "7C", "5C", "2S", "3H", "4D", "8S", "JC"],
		"draw": ["KS", "KD", "KH", "KC", "9C", "9H", "7D", "7S", "4S", "4H", "9D", "7H", "4C"],
		"lose": ["2C", "AH", "5D", "AC", "8H", "6S", "JS", "9C", "3D", "TD", "4S", "7C", "KH"],
	}
	var m := PokerMatch.new(Deck.stacked(order[outcome]))
	m.player_draw([])
	return m


func test_chips_never_go_negative() -> void:
	var s := GameState.new()
	s.add_chips(30, "test")
	check(not s.spend_chips(50, "too much"), "overspend rejected")
	check_eq(s.chips_balance, 30, "balance unchanged")
	check(not s.spend_chips(-5, "negative"), "negative spend rejected")
	check(s.spend_chips(30, "all"), "exact spend ok")
	check_eq(s.chips_balance, 0, "zero balance")
	check_eq(s.chips_ledger.size(), 2, "ledger has add and spend")
	check_eq(s.chips_ledger[1]["delta"], -30, "ledger delta")


func test_rewards_per_outcome_with_first_bonus_once() -> void:
	var expected := {"win": [100, 160], "draw": [70, 100], "lose": [60, 80]}
	for outcome in expected:
		var s := GameState.new()
		var r1 := PokerRewards.settle(s, _finished_match(outcome), ECONOMY)
		check_eq(r1["outcome"], outcome, "outcome " + outcome)
		check_eq(s.chips_balance, expected[outcome][0], "first hand balance " + outcome)
		check_eq(r1["bonus"], 40, "first bonus " + outcome)
		var r2 := PokerRewards.settle(s, _finished_match(outcome), ECONOMY)
		check_eq(r2["bonus"], 0, "no second bonus " + outcome)
		check_eq(s.chips_balance, expected[outcome][1], "second hand balance " + outcome)
		check_eq(s.poker_hands_completed, 2, "hands counted " + outcome)


func test_first_hand_always_affords_the_lamp() -> void:
	for outcome in ["win", "draw", "lose"]:
		var s := GameState.new()
		PokerRewards.settle(s, _finished_match(outcome), ECONOMY)
		check(s.chips_balance >= 50, "after first %s hand the 50-chip lamp is affordable" % outcome)


func test_a_hand_is_paid_only_once() -> void:
	var s := GameState.new()
	var m := _finished_match("win")
	check(PokerRewards.settle(s, m, ECONOMY)["ok"], "first settle")
	check(not PokerRewards.settle(s, m, ECONOMY)["ok"], "second settle rejected")
	check_eq(s.chips_balance, 100, "paid once")
	var unfinished := PokerMatch.new(Deck.shuffled(5))
	check(not PokerRewards.settle(s, unfinished, ECONOMY)["ok"], "unfinished hand not paid")


func test_purchase_and_placement() -> void:
	var s := GameState.new()
	s.add_chips(60, "test")
	check(s.purchase(LAMP, 50), "purchase")
	check_eq(s.chips_balance, 10, "paid 50")
	check_eq(s.owned_count(LAMP), 1, "in storage")
	check(s.collection.has(LAMP), "recorded in collection")
	check(not s.purchase(LAMP, 50), "cannot afford second")
	check_eq(s.chips_balance, 10, "balance unchanged after failed purchase")

	check(s.place_item("slot_window", LAMP), "place")
	check_eq(s.owned_count(LAMP), 0, "storage empty")
	check_eq(s.placement_at("slot_window"), LAMP, "slot holds lamp")
	check(not s.place_item("slot_table", LAMP), "cannot place without owning another")
	check(s.remove_placement("slot_window"), "remove")
	check_eq(s.owned_count(LAMP), 1, "back in storage")
	check(s.place_item("slot_table", LAMP), "place again")
	s.grant_item(LAMP)
	check(not s.place_item("slot_table", LAMP), "occupied slot rejected")


func test_serialization_round_trip() -> void:
	var s := GameState.new()
	s.player_name = "테스터"
	s.add_chips(60, "a")
	s.set_flag("intro_met_lumi")
	s.purchase(LAMP, 50)
	s.place_item("slot_window", LAMP)
	s.poker_hands_completed = 3
	s.current_scene = "player_home"
	s.player_position = Vector2(120, 340)
	s.has_player_position = true
	var t := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check_eq(t.to_dict(), s.to_dict(), "round trip through JSON")
	check_eq(t.chips_balance, 10, "chips int")
	check_eq(typeof(t.chips_balance), TYPE_INT, "chips typed int")
