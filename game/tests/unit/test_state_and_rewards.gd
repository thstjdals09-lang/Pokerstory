extends "res://tests/test_case.gd"
## Chip economy (Economy v0.2.2): fixed stake 20, win returns 40, draw returns 20, loss returns 0,
## no loss reward, no first-play bonus. Unfinished hands are saved and resumed, never refunded.

const ECONOMY := {"starting_chips": 40, "stake": 20, "payout_win": 40, "payout_draw": 20, "payout_lose": 0}
const STAR_SENSE := {"id": "ability.star_sense", "uses_per_match": 1, "effect": "reveal_opponent_pair_or_better"}
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


func _codes(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(c.code())
	return out


## Simulates quit + restart: the hand goes through JSON like a save file.
func _reload(m: PokerMatch) -> PokerMatch:
	return PokerMatch.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))


func test_interrupted_hand_restores_exactly() -> void:
	var s := _state_with(40)
	PokerEconomy.place_stake(s, ECONOMY)
	var m := PokerMatch.new(Deck.shuffled(2024))
	m.use_ability(STAR_SENSE)
	s.poker_in_progress = m.to_dict()
	var saved := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check_eq(saved.chips_balance, 20, "stake taken once")
	check_eq(saved.pending_poker_stake, 20, "stake still pending")
	var r := PokerMatch.from_dict(saved.poker_in_progress)
	check(r != null, "hand restored")
	check_eq(_codes(r.player_hand), _codes(m.player_hand), "same player hand")
	check_eq(_codes(r.opponent_hand), _codes(m.opponent_hand), "same opponent hand")
	check_eq(r.deck.codes(), m.deck.codes(), "same remaining deck order")
	check(not r.can_use_ability(STAR_SENSE), "ability stays used")
	check_eq(r.ability_results, m.ability_results, "ability result kept")
	check_eq(r.phase, PokerMatch.Phase.DRAW, "still before the draw")


func test_restart_cannot_change_the_result() -> void:
	for seed_value in [3, 77, 4096, 90210]:
		var original := PokerMatch.new(Deck.shuffled(seed_value))
		var resumed := _reload(original)
		original.player_draw([0, 1])
		resumed.player_draw([0, 1])
		check_eq(_codes(resumed.player_hand), _codes(original.player_hand), "same draws seed %d" % seed_value)
		check_eq(_codes(resumed.opponent_hand), _codes(original.opponent_hand), "same opponent draw seed %d" % seed_value)
		check_eq(resumed.outcome, original.outcome, "same outcome seed %d" % seed_value)


func test_resumed_hand_settles_once() -> void:
	var s := _state_with(40)
	PokerEconomy.place_stake(s, ECONOMY)
	var m := PokerMatch.new(Deck.stacked(ORDERS["win"]))
	s.poker_in_progress = m.to_dict()
	var s2 := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	var r := PokerMatch.from_dict(s2.poker_in_progress)
	r.player_draw([])
	check(PokerEconomy.settle(s2, r, ECONOMY)["ok"], "settled after resume")
	check_eq(s2.chips_balance, 60, "win after resume: 20 + 40")
	check(not PokerEconomy.settle(s2, r, ECONOMY)["ok"], "no second settlement")
	var stakes := 0
	for e in s2.chips_ledger:
		if e["reason"] == "poker_stake":
			stakes += 1
	check_eq(stakes, 1, "stake charged once in total")


func test_invalid_saved_hand_is_rejected() -> void:
	var good := PokerMatch.new(Deck.shuffled(5)).to_dict()
	var dup := good.duplicate(true)
	dup["player_hand"][0] = dup["opponent_hand"][0]
	check(PokerMatch.from_dict(dup) == null, "duplicate card rejected")
	var short := good.duplicate(true)
	short["deck"].pop_back()
	check(PokerMatch.from_dict(short) == null, "missing card rejected")
	var done := good.duplicate(true)
	done["phase"] = PokerMatch.Phase.SHOWDOWN
	check(PokerMatch.from_dict(done) == null, "finished hand is never restored")


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
	s.poker_in_progress = PokerMatch.new(Deck.shuffled(11)).to_dict()
	s.current_scene = "player_home"
	s.player_position = Vector2(120, 340)
	s.has_player_position = true
	var t := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check_eq(t.to_dict(), s.to_dict(), "round trip through JSON")
	check_eq(typeof(t.chips_balance), TYPE_INT, "chips typed int")
