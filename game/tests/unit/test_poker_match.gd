extends "res://tests/test_case.gd"
## Dealing alternates player, opponent, player, ... so in a stacked deck
## indices 0,2,4,6,8 are the player's cards, 1,3,5,7,9 the opponent's, and 10+ are draws.

const STAR_SENSE := {
	"id": "ability.star_sense",
	"uses_per_match": 1,
	"effect": "reveal_opponent_pair_or_better",
}


func _codes(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(c.code())
	return out


func _stack(player: String, opponent: String, draws: String = "") -> Deck:
	var p := player.split(" ", false)
	var o := opponent.split(" ", false)
	var order: Array = []
	for i in 5:
		order.append(p[i])
		order.append(o[i])
	order.append_array(Array(draws.split(" ", false)))
	return Deck.stacked(order)


func test_deal_five_each() -> void:
	var m := PokerMatch.new(_stack("AS AH KD 7C 2S", "QS QH 9D 5C 3H"))
	check_eq(_codes(m.player_hand), ["AS", "AH", "KD", "7C", "2S"], "player hand")
	check_eq(_codes(m.opponent_hand), ["QS", "QH", "9D", "5C", "3H"], "opponent hand")
	check_eq(m.phase, PokerMatch.Phase.DRAW, "phase")


func test_draw_replaces_selected_cards_in_order_then_opponent_draws() -> void:
	var m := PokerMatch.new(_stack("AS AH KD 7C 2S", "QS QH 9D 5C 3H", "6H 4D 8S JC"))
	check(m.player_draw([4]), "draw accepted")
	check_eq(_codes(m.player_hand), ["AS", "AH", "KD", "7C", "6H"], "player got the next card")
	check_eq(m.opponent_discards, [2, 3, 4], "opponent kept its pair")
	check_eq(_codes(m.opponent_hand), ["QS", "QH", "4D", "8S", "JC"], "opponent drew after the player")
	check_eq(m.outcome, 1, "pair of aces beats pair of queens")
	check_eq(m.phase, PokerMatch.Phase.SHOWDOWN, "showdown")


func test_invalid_draws_are_rejected() -> void:
	var m := PokerMatch.new(Deck.shuffled(7))
	var before := _codes(m.player_hand)
	check(not m.player_draw([0, 1, 2, 3]), "more than 3 rejected")
	check(not m.player_draw([1, 1]), "duplicate rejected")
	check(not m.player_draw([5]), "out of range rejected")
	check(not m.player_draw([-1]), "negative rejected")
	check_eq(_codes(m.player_hand), before, "hand unchanged after rejected draws")
	check(m.player_draw([]), "standing pat accepted")
	check(not m.player_draw([]), "second draw rejected")


func test_draw_and_lose_outcomes() -> void:
	var tie := PokerMatch.new(_stack("KS KH 9C 7D 4S", "KD KC 9H 7S 4H", "9D 7H 4C"))
	tie.player_draw([])
	check_eq(tie.outcome, 0, "identical ranks draw")
	var lose := PokerMatch.new(_stack("2C 5D 8H JS 3D", "AH AC 6S 9C TD", "4S 7C KH"))
	lose.player_draw([])
	check_eq(lose.outcome, -1, "high card loses to pair of aces")


func test_star_sense_reveals_only_pair_or_better_once() -> void:
	var pair := PokerMatch.new(_stack("2C 5D 8H JS 3D", "AH AC 6S 9C TD"))
	var r := pair.use_ability(STAR_SENSE)
	check(r["ok"], "first use ok")
	check_eq(r["pair_or_better"], true, "opponent has a pair")
	var keys: Array = r.keys()
	keys.sort()
	check_eq(keys, ["effect", "ok", "pair_or_better"], "result carries no card data")
	check(not pair.use_ability(STAR_SENSE)["ok"], "second use rejected")

	var nothing := PokerMatch.new(_stack("2C 5D 8H JS 3D", "AH KC 6S 9C TD"))
	check_eq(nothing.use_ability(STAR_SENSE)["pair_or_better"], false, "opponent has high card")


func test_ability_unavailable_after_draw() -> void:
	var m := PokerMatch.new(Deck.shuffled(3))
	m.player_draw([])
	check(not m.can_use_ability(STAR_SENSE), "no ability in showdown")


func test_opponent_ignores_player_hand() -> void:
	# Same opponent cards and same draw pile, different player cards -> identical opponent play.
	var a := PokerMatch.new(_stack("2C 5D 8H JS 3D", "AH AC 6S 9C TD", "4S 7C KH"))
	var b := PokerMatch.new(_stack("QS QD QH JC 3C", "AH AC 6S 9C TD", "4S 7C KH"))
	a.player_draw([])
	b.player_draw([])
	check_eq(a.opponent_discards, b.opponent_discards, "same discards")
	check_eq(_codes(a.opponent_hand), _codes(b.opponent_hand), "same final hand")


func test_same_seed_and_choices_reproduce_result() -> void:
	for seed_value in [1, 99, 123456]:
		var a := PokerMatch.new(Deck.shuffled(seed_value))
		var b := PokerMatch.new(Deck.shuffled(seed_value))
		a.player_draw([0, 2])
		b.player_draw([0, 2])
		check_eq(_codes(a.player_hand), _codes(b.player_hand), "player hand seed %d" % seed_value)
		check_eq(_codes(a.opponent_hand), _codes(b.opponent_hand), "opponent hand seed %d" % seed_value)
		check_eq(a.outcome, b.outcome, "outcome seed %d" % seed_value)
