extends "res://tests/test_case.gd"


func _draw_all(deck: Deck) -> Array:
	var codes: Array = []
	while deck.remaining() > 0:
		codes.append(deck.draw_one().code())
	return codes


func test_standard_deck_has_52_unique_cards() -> void:
	var codes := _draw_all(Deck.shuffled(1))
	check_eq(codes.size(), 52, "card count")
	var unique := {}
	for c in codes:
		unique[c] = true
	check_eq(unique.size(), 52, "unique cards")


func test_same_seed_same_order_different_seed_different_order() -> void:
	check_eq(_draw_all(Deck.shuffled(42)), _draw_all(Deck.shuffled(42)), "same seed")
	check(_draw_all(Deck.shuffled(42)) != _draw_all(Deck.shuffled(43)), "different seeds should differ")


func test_stacked_deck_puts_cards_on_top() -> void:
	var codes := _draw_all(Deck.stacked(["AS", "KD", "2C"]))
	check_eq(codes.slice(0, 3), ["AS", "KD", "2C"], "top cards")
	check_eq(codes.size(), 52, "still 52 cards")
	check_eq(codes.count("AS"), 1, "no duplicate AS")


func test_ai_keeps_straight_or_better() -> void:
	check_eq(PokerAI.choose_discards(hand("5S 6D 7C 8H 9S")), [], "straight")
	check_eq(PokerAI.choose_discards(hand("2H 7H 9H JH KH")), [], "flush")
	check_eq(PokerAI.choose_discards(hand("9S 9D 9C KH KS")), [], "full house")
	check_eq(PokerAI.choose_discards(hand("9S 9D 9C 9H 2S")), [], "four of a kind")


func test_ai_pair_rules() -> void:
	check_eq(PokerAI.choose_discards(hand("9S 2D 9C KH 5S")), [1, 3, 4], "one pair: replace three others")
	check_eq(PokerAI.choose_discards(hand("9S 2D 9C 2H 5S")), [4], "two pair: replace the fifth card")
	check_eq(PokerAI.choose_discards(hand("9S 2D 9C 9H 5S")), [1, 4], "three of a kind: replace two others")


func test_ai_high_card_rules() -> void:
	check_eq(PokerAI.choose_discards(hand("2H 7H 9H JH KS")), [4], "four to a flush: replace odd card")
	check_eq(PokerAI.choose_discards(hand("AS 3D 9C 4H KS")), [1, 2, 3], "keep two highest (A, K)")


func test_ai_never_discards_more_than_limit() -> void:
	check(PokerAI.choose_discards(hand("AS 3D 9C 4H KS"), 2).size() <= 2, "limit 2")
	check(PokerAI.choose_discards(hand("AS 3D 9C 4H KS"), 3).size() <= 3, "limit 3")
