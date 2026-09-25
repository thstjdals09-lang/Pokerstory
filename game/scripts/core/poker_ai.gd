class_name PokerAI
extends RefCounted
## The opponent's draw rule. It is public and deterministic, and it only ever receives
## the opponent's own hand, so it cannot read the player's hidden cards.
##   Straight or better: keep all five.
##   Three of a kind: replace the two other cards.
##   Two pair: replace the fifth card.
##   One pair: replace the three other cards.
##   High card: with four cards of one suit, replace the odd card;
##              otherwise keep the two highest cards and replace the other three.
## Personas (content v0.3, 05_poker/03) change only how boldly the rule replaces cards; every
## persona still receives nothing but its own five cards:
##   steady, keep_pairs: the rule above.
##   cautious, friendly: keep one more card (high card: replace 2; one pair: replace 2 kickers).
##   curious: chases fresh cards (high card: always replace 3, even with four of a suit).


## Returns the sorted indices (0..4) of the cards to replace, at most `max_discards`.
static func choose_discards(own_hand: Array, max_discards: int = 3, persona: String = "steady") -> Array:
	var category: int = HandEvaluator.evaluate(own_hand)["category"]
	var discards: Array = []
	if category >= HandEvaluator.Category.STRAIGHT:
		return discards
	var careful := persona == "cautious" or persona == "friendly"
	if category == HandEvaluator.Category.HIGH_CARD and (careful or persona == "curious"):
		var order: Array = range(own_hand.size())
		order.sort_custom(func(a, b): return own_hand[a].rank < own_hand[b].rank or (own_hand[a].rank == own_hand[b].rank and a < b))
		discards = order.slice(0, 2 if careful else 3)
		discards.sort()
		return discards.slice(0, max_discards)
	if category == HandEvaluator.Category.ONE_PAIR and careful:
		var counts := {}
		for c in own_hand:
			counts[c.rank] = int(counts.get(c.rank, 0)) + 1
		var kickers: Array = []
		for i in own_hand.size():
			if counts[own_hand[i].rank] == 1:
				kickers.append(i)
		kickers.sort_custom(func(a, b): return own_hand[a].rank < own_hand[b].rank or (own_hand[a].rank == own_hand[b].rank and a < b))
		discards = kickers.slice(0, 2)
		discards.sort()
		return discards

	if category == HandEvaluator.Category.HIGH_CARD:
		var suit_counts := {}
		for c in own_hand:
			suit_counts[c.suit] = int(suit_counts.get(c.suit, 0)) + 1
		var flush_suit := -1
		for s in suit_counts:
			if suit_counts[s] == 4:
				flush_suit = s
		if flush_suit >= 0:
			for i in own_hand.size():
				if own_hand[i].suit != flush_suit:
					discards.append(i)
		else:
			var order: Array = range(own_hand.size())
			order.sort_custom(func(a, b): return own_hand[a].rank < own_hand[b].rank)
			discards = order.slice(0, 3)
	else:
		# pair-based hands: replace every card that is not part of a group
		var counts := {}
		for c in own_hand:
			counts[c.rank] = int(counts.get(c.rank, 0)) + 1
		for i in own_hand.size():
			if counts[own_hand[i].rank] == 1:
				discards.append(i)

	discards.sort()
	if discards.size() > max_discards:
		discards = discards.slice(0, max_discards)
	return discards
