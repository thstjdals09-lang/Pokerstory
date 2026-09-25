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
##   keep_pairs: a pair with an ace kicker keeps the ace (replaces 2).
##   chaser: chases four to a flush or a straight (replaces 1), even from a small pair.
##   showman: breaks a two pair to keep only the higher pair and draw 3 (a flashy mistake).


## Returns the sorted indices (0..4) of the cards to replace, at most `max_discards`.
static func choose_discards(own_hand: Array, max_discards: int = 3, persona: String = "steady") -> Array:
	var category: int = HandEvaluator.evaluate(own_hand)["category"]
	var discards: Array = []
	if category >= HandEvaluator.Category.STRAIGHT:
		return discards
	var careful := persona == "cautious" or persona == "friendly"
	if persona == "chaser" and category <= HandEvaluator.Category.ONE_PAIR:
		var chase := _draw_to_flush_or_straight(own_hand, category)
		if not chase.is_empty():
			return chase
	if persona == "showman" and category == HandEvaluator.Category.TWO_PAIR:
		var counts2 := {}
		for c in own_hand:
			counts2[c.rank] = int(counts2.get(c.rank, 0)) + 1
		var top := -1
		for r in counts2:
			if counts2[r] == 2 and r > top:
				top = r
		for i in own_hand.size():
			if own_hand[i].rank != top:
				discards.append(i)
		return discards
	if persona == "keep_pairs" and category == HandEvaluator.Category.ONE_PAIR:
		var counts3 := {}
		for c in own_hand:
			counts3[c.rank] = int(counts3.get(c.rank, 0)) + 1
		var has_ace_kicker := false
		for c in own_hand:
			has_ace_kicker = has_ace_kicker or (c.rank == 14 and counts3[14] == 1)
		if has_ace_kicker:
			for i in own_hand.size():
				if counts3[own_hand[i].rank] == 1 and own_hand[i].rank != 14:
					discards.append(i)
			return discards
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


## Four cards to a flush, or four distinct ranks within a span of five (a straight draw):
## the index of the odd card. Empty when there is no such draw. Own cards only.
static func _draw_to_flush_or_straight(own_hand: Array, category: int) -> Array:
	var suit_counts := {}
	for c in own_hand:
		suit_counts[c.suit] = int(suit_counts.get(c.suit, 0)) + 1
	for s in suit_counts:
		if suit_counts[s] == 4:
			for i in own_hand.size():
				if own_hand[i].suit != s:
					return [i]
	if category != HandEvaluator.Category.HIGH_CARD:
		return []
	for skip in own_hand.size():
		var ranks: Array = []
		for i in own_hand.size():
			if i != skip:
				ranks.append(own_hand[i].rank)
		ranks.sort()
		if ranks[3] - ranks[0] <= 4:
			return [skip]
	return []
