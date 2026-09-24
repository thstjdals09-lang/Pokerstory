class_name Deck
extends RefCounted
## An ordered 52-card deck without jokers. draw_one() takes the top card (index 0).

var seed_used := 0
var _cards: Array = []


static func standard_cards() -> Array:
	var cards: Array = []
	for s in 4:
		for r in range(2, 15):
			cards.append(Card.new(r, s))
	return cards


## Fisher-Yates shuffle driven by a seeded RNG: the same seed always gives the same order.
static func shuffled(seed_value: int) -> Deck:
	var deck := Deck.new()
	deck.seed_used = seed_value
	var cards := standard_cards()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = cards[i]
		cards[i] = cards[j]
		cards[j] = tmp
	deck._cards = cards
	return deck


## Test/debug deck: `top_codes` on top in the given order, then the remaining cards in standard order.
static func stacked(top_codes: Array) -> Deck:
	var deck := Deck.new()
	var used := {}
	var cards: Array = []
	for c in top_codes:
		var card := Card.from_code(str(c))
		assert(card != null, "invalid card code in stacked deck")
		assert(not used.has(card.code()), "duplicate card in stacked deck")
		used[card.code()] = true
		cards.append(card)
	for card in standard_cards():
		if not used.has(card.code()):
			cards.append(card)
	deck._cards = cards
	return deck


func draw_one() -> Card:
	if _cards.is_empty():
		push_error("Deck is empty")
		return null
	return _cards.pop_front()


func remaining() -> int:
	return _cards.size()
