extends "res://tests/test_case.gd"
## Chip economy (Economy v0.2.1): fixed stake 20, win returns 40, draw returns 20, loss returns 0,
## no loss reward, no first-play bonus.

const ECONOMY := {"starting_chips": 100, "stake": 20, "payout_win": 40, "payout_draw": 20, "payout_lose": 0}
const LAMP := "furniture.lamp_small"
const ORDERS := {
	"win": ["AS", "QS", "AH", "QH", "KD", "9D", "7C", "5C", "2S", "3H", "4D", "8S", "JC"],
	"draw": ["KS", "KD", "KH", "KC", "9C", "9H", "7D", "7S", "4S", "4H", "9D", "7H", "4C"],
	"lose": ["2C", "AH", "5D", "AC", "8H", "6S", "JS", "9C", "3D", "TD", "4S", "7C", "KH"],
}


func _state_with(chips: int) -> GameState:
	var s := GameState.new()
	s.add_chips(chips, "test")
	return s


## Takes the stake, plays the stacked hand standing pat, and settles it.
func _play(s: GameState, outcome: String) -> Dictionary:
	if not PokerEconomy.place_stake(s, ECONOMY):
		return {"ok": false, "joined": false}
	var m := PokerMatch.new(Deck.stacked(ORDERS[outcome]))
	m.player_draw([])
	return PokerEconomy.settle(s, m, ECONOMY)


func test_chips_never_go_negative() -> void:
	var s := _state_with(30)
	check(not s.spend_chips(50, "too much"), "overspend rejected")
	check_eq(s.chips_balance, 30, "balance unchanged")
	check(not s.spend_chips(-5, "negative"), "negative spend rejected")
	check(s.spend_chips(30, "all"), "exact spend ok")
	check_eq(s.chips_balance, 0, "zero balance")
	check_eq(s.chips_ledger[1]["delta"], -30, "ledger delta")


func test_win_increases_draw_keeps_loss_decreases() -> void:
	var expected := {"win": 120, "draw": 100, "lose": 80}
	var net := {"win": 20, "draw": 0, "lose": -20}
	for outcome in expected:
		var s := _state_with(100)
		var r := _play(s, outcome)
		check(r["ok"], "settled " + outcome)
		check_eq(r["outcome"], outcome, "outcome " + outcome)
		check_eq(int(r["net"]), net[outcome], "net " + outcome)
		check_eq(s.chips_balance, expected[outcome], "balance after " + outcome)
		check_eq(s.pending_poker_stake, 0, "no stake left pending " + outcome)


func test_ledger_records_stake_and_payout() -> void:
	var s := GameState.new()
	s.add_chips(100, "starting_chips")
	_play(s, "win")
	_play(s, "draw")
	_play(s, "lose")
	var reasons: Array = []
	var total := 0
	for e in s.chips_ledger:
		reasons.append(e["reason"])
		total += int(e["delta"])
	check_eq(reasons, ["starting_chips", "poker_stake", "poker_payout_win", "poker_stake", "poker_payout_draw", "poker_stake"], "ledger reasons (a loss pays nothing)")
	check_eq(total, s.chips_balance, "ledger sums to balance")
	check_eq(s.chips_balance, 100, "+20, 0, -20")


func test_no_loss_reward_and_no_first_bonus() -> void:
	var s := _state_with(20)
	var r := _play(s, "lose")
	check_eq(int(r["payout"]), 0, "loss pays nothing")
	check_eq(s.chips_balance, 0, "lost the whole stake")
	for e in s.chips_ledger:
		check(not str(e["reason"]).contains("bonus"), "no bonus entries")


func test_cannot_join_below_stake() -> void:
	var s := _state_with(19)
	check(not PokerEconomy.can_join(s, ECONOMY), "19 chips cannot join")
	check(not PokerEconomy.place_stake(s, ECONOMY), "stake refused")
	check_eq(s.chips_balance, 19, "balance untouched")
	check_eq(s.chips_ledger.size(), 1, "no ledger entry")
	s.add_chips(1, "test")
	check(PokerEconomy.place_stake(s, ECONOMY), "exactly 20 can join")
	check_eq(s.chips_balance, 0, "stake taken at start")
	check_eq(s.pending_poker_stake, 20, "stake pending")
	check(not PokerEconomy.can_join(s, ECONOMY), "no second hand while one is pending")


func test_a_hand_is_settled_only_once() -> void:
	var s := _state_with(100)
	PokerEconomy.place_stake(s, ECONOMY)
	var m := PokerMatch.new(Deck.stacked(ORDERS["win"]))
	m.player_draw([])
	check(PokerEconomy.settle(s, m, ECONOMY)["ok"], "first settle")
	check(not PokerEconomy.settle(s, m, ECONOMY)["ok"], "second settle rejected")
	check_eq(s.chips_balance, 120, "paid once")
	PokerEconomy.place_stake(s, ECONOMY)
	var unfinished := PokerMatch.new(Deck.shuffled(5))
	check(not PokerEconomy.settle(s, unfinished, ECONOMY)["ok"], "unfinished hand not paid")


func test_fold_keeps_the_stake_lost() -> void:
	var s := _state_with(100)
	PokerEconomy.place_stake(s, ECONOMY)
	var m := PokerMatch.new(Deck.shuffled(9))
	check(PokerEconomy.fold(s, m)["ok"], "fold before showdown")
	check_eq(s.chips_balance, 80, "stake lost on fold")
	check_eq(s.pending_poker_stake, 0, "nothing pending")
	check_eq(s.poker_record["fold"], 1, "fold counted")
	check(not PokerEconomy.settle(s, m, ECONOMY)["ok"], "folded hand cannot be settled")
	check(not PokerEconomy.fold(s, m)["ok"], "cannot fold twice")


func test_interrupted_hand_is_refunded_once() -> void:
	var s := _state_with(100)
	PokerEconomy.place_stake(s, ECONOMY)
	var reloaded := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check_eq(reloaded.chips_balance, 80, "stake was saved as taken")
	check_eq(PokerEconomy.void_pending(reloaded), 20, "refund on load")
	check_eq(reloaded.chips_balance, 100, "balance restored")
	check_eq(PokerEconomy.void_pending(reloaded), 0, "second refund impossible")
	check_eq(reloaded.chips_ledger.back()["reason"], "poker_void_refund", "refund recorded")


func test_purchase_and_placement() -> void:
	var s := _state_with(60)
	check(s.purchase(LAMP, 50), "purchase")
	check_eq(s.chips_balance, 10, "paid 50")
	check_eq(s.owned_count(LAMP), 1, "in storage")
	check(s.collection.has(LAMP), "recorded in collection")
	check(not s.purchase(LAMP, 50), "cannot afford second")
	check(s.place_item("slot_window", LAMP), "place")
	check_eq(s.placement_at("slot_window"), LAMP, "slot holds lamp")
	check(not s.place_item("slot_table", LAMP), "cannot place without owning another")
	check(s.remove_placement("slot_window"), "remove")
	check_eq(s.owned_count(LAMP), 1, "back in storage")


func test_serialization_round_trip() -> void:
	var s := _state_with(60)
	s.player_name = "테스터"
	s.set_flag("intro_met_lumi")
	s.purchase(LAMP, 50)
	s.place_item("slot_window", LAMP)
	s.poker_hands_completed = 3
	s.time_of_day = "evening"
	s.quests["quest.sera_delivery"] = "completed"
	s.jobs_completed = 2
	s.pending_poker_stake = 20
	s.current_scene = "player_home"
	s.player_position = Vector2(120, 340)
	s.has_player_position = true
	var t := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check_eq(t.to_dict(), s.to_dict(), "round trip through JSON")
	check_eq(typeof(t.chips_balance), TYPE_INT, "chips typed int")
