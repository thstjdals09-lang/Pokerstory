extends "res://tests/test_case.gd"
## Executable specification of the 5-card hand ranking used in Project 20 (spec v0.2 section 5).
## Card codes: rank 2-9, T, J, Q, K, A + suit S(♠) H(♥) D(♦) C(♣).

const C := HandEvaluator.Category


func _cat(codes: String) -> int:
	return HandEvaluator.evaluate(hand(codes))["category"]


func _cmp(a: String, b: String) -> int:
	return HandEvaluator.compare(HandEvaluator.evaluate(hand(a)), HandEvaluator.evaluate(hand(b)))


func test_categories_are_detected() -> void:
	check_eq(_cat("AS KD 9C 7H 2S"), C.HIGH_CARD, "high card")
	check_eq(_cat("KS KD 9C 7H 2S"), C.ONE_PAIR, "one pair")
	check_eq(_cat("KS KD 9C 9H 2S"), C.TWO_PAIR, "two pair")
	check_eq(_cat("9S 9D 9C 7H 2S"), C.THREE_OF_A_KIND, "three of a kind")
	check_eq(_cat("5S 6D 7C 8H 9S"), C.STRAIGHT, "straight")
	check_eq(_cat("AS 2D 3C 4H 5S"), C.STRAIGHT, "wheel A-2-3-4-5 is a straight")
	check_eq(_cat("TS JD QC KH AS"), C.STRAIGHT, "broadway T-J-Q-K-A is a straight")
	check_eq(_cat("2H 7H 9H JH KH"), C.FLUSH, "flush")
	check_eq(_cat("9S 9D 9C KH KS"), C.FULL_HOUSE, "full house")
	check_eq(_cat("9S 9D 9C 9H 2S"), C.FOUR_OF_A_KIND, "four of a kind")
	check_eq(_cat("5H 6H 7H 8H 9H"), C.STRAIGHT_FLUSH, "straight flush")
	check_eq(_cat("TH JH QH KH AH"), C.STRAIGHT_FLUSH, "royal flush is a straight flush")


func test_ace_does_not_wrap_around() -> void:
	check_eq(_cat("QS KD AC 2H 3S"), C.HIGH_CARD, "Q-K-A-2-3 is not a straight")
	check_eq(_cat("JS QD KC AH 2S"), C.HIGH_CARD, "J-Q-K-A-2 is not a straight")


func test_category_order() -> void:
	var ladder := [
		"AS KD 9C 7H 2S",  # high card
		"2S 2D 3C 4H 6S",  # one pair
		"2S 2D 3C 3H 4S",  # two pair
		"2S 2D 2C 3H 4S",  # three of a kind
		"AS 2D 3C 4H 5S",  # straight (lowest)
		"2H 3H 4H 5H 7H",  # flush (lowest)
		"2S 2D 2C 3H 3S",  # full house (lowest)
		"2S 2D 2C 2H 3S",  # four of a kind (lowest)
		"AH 2H 3H 4H 5H",  # straight flush (lowest)
	]
	for i in range(1, ladder.size()):
		check_eq(_cmp(ladder[i], ladder[i - 1]), 1, "%s should beat %s" % [ladder[i], ladder[i - 1]])
		check_eq(_cmp(ladder[i - 1], ladder[i]), -1, "%s should lose to %s" % [ladder[i - 1], ladder[i]])


func test_high_card_compares_all_five_cards() -> void:
	check_eq(_cmp("AS KD 9C 7H 3S", "AD KC 9H 7S 2D"), 1, "fifth card decides")
	check_eq(_cmp("AS KD 9C 6H 5S", "AD KC 9H 7S 2D"), -1, "fourth card decides")
	check_eq(_cmp("AS QD JC 9H 8S", "KD QC JH 9S 8D"), 1, "first card decides")


func test_one_pair_then_kickers() -> void:
	check_eq(_cmp("AS AD 3C 4H 5S", "KS KD QC JH 9S"), 1, "higher pair wins")
	check_eq(_cmp("KS KD AC 4H 3S", "KH KC QD JH 9S"), 1, "same pair: highest kicker")
	check_eq(_cmp("KS KD AC 9H 3S", "KH KC AD 9S 2D"), 1, "same pair: third kicker")


func test_two_pair_order() -> void:
	check_eq(_cmp("KS KD 2C 2H 3S", "QS QD JC JH AS"), 1, "higher top pair wins")
	check_eq(_cmp("KS KD 9C 9H 3S", "KH KC 8D 8H AS"), 1, "same top pair: higher second pair")
	check_eq(_cmp("KS KD 9C 9H 4S", "KH KC 9D 9S 3D"), 1, "same pairs: kicker")


func test_three_four_and_full_house() -> void:
	check_eq(_cmp("9S 9D 9C 2H 3S", "8S 8D 8C AH KS"), 1, "higher three of a kind")
	check_eq(_cmp("9S 9D 9C KH KS", "8S 8D 8C AH AS"), 1, "full house compares three first")
	check_eq(_cmp("9S 9D 9C KH 2S", "8S 8D 8C AH AS"), -1, "three of a kind loses to full house")
	check_eq(_cmp("9S 9D 9C 9H 2S", "8S 8D 8C 8H AS"), 1, "higher four of a kind")


func test_straights_and_flushes() -> void:
	check_eq(_cmp("2S 3D 4C 5H 6S", "AS 2D 3C 4H 5S"), 1, "6-high straight beats the wheel")
	check_eq(_cmp("TS JD QC KH AS", "9S TD JC QH KS"), 1, "ace-high straight beats king-high")
	check_eq(_cmp("AH 9H 7H 5H 3H", "KS QS JS 9S 7S"), 1, "flush: highest card")
	check_eq(_cmp("AH KH 7H 5H 3H", "AS KS 7S 5S 2S"), 1, "flush: fifth card")
	check_eq(_cmp("6H 7H 8H 9H TH", "AS 2S 3S 4S 5S"), 1, "10-high straight flush beats 5-high")


func test_exact_ties_are_draws_and_suits_never_break_ties() -> void:
	check_eq(_cmp("KS KD 9C 7H 4S", "KH KC 9D 7S 4H"), 0, "same pair and kickers")
	check_eq(_cmp("AS KD 9C 7H 2S", "AH KC 9D 7S 2D"), 0, "same high cards")
	check_eq(_cmp("5S 6D 7C 8H 9S", "5H 6C 7D 8S 9H"), 0, "same straight")
	check_eq(_cmp("AH 9H 7H 5H 3H", "AS 9S 7S 5S 3S"), 0, "same flush ranks")


func test_names() -> void:
	check_eq(HandEvaluator.evaluate(hand("KS KD 9C 7H 2S"))["name"], "원페어 (K)", "pair name")
	check_eq(HandEvaluator.evaluate(hand("KS KD 9C 9H 2S"))["name"], "투페어 (K, 9)", "two pair name")
	check_eq(HandEvaluator.evaluate(hand("AS 2D 3C 4H 5S"))["name"], "스트레이트 (5 하이)", "wheel name")
	check_eq(HandEvaluator.evaluate(hand("TH JH QH KH AH"))["name"], "로열 스트레이트 플러시", "royal name")
	check_eq(HandEvaluator.evaluate(hand("9S 9D 9C KH KS"))["name"], "풀하우스 (9, K)", "full house name")
