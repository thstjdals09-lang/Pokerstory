class_name HandEvaluator
extends RefCounted
## Standard 5-card poker hand ranking. No wild cards. Suits never break ties.
##
## Category order (low -> high): high card, one pair, two pair, three of a kind, straight,
## flush, full house, four of a kind, straight flush.
## A-2-3-4-5 is the lowest straight (5-high). The ace does not wrap (Q-K-A-2-3 is not a straight).
## Hands in the same category compare their tiebreak lists left to right.
## Same category and same tiebreak list is a draw.
## The executable version of these rules is tests/unit/test_hand_evaluator.gd.

enum Category {
	HIGH_CARD,
	ONE_PAIR,
	TWO_PAIR,
	THREE_OF_A_KIND,
	STRAIGHT,
	FLUSH,
	FULL_HOUSE,
	FOUR_OF_A_KIND,
	STRAIGHT_FLUSH,
}

const CATEGORY_NAMES := [
	"하이카드", "원페어", "투페어", "트리플", "스트레이트",
	"플러시", "풀하우스", "포카드", "스트레이트 플러시",
]


## Returns {"category": int, "tiebreak": Array[int], "name": String}.
static func evaluate(cards: Array) -> Dictionary:
	assert(cards.size() == 5, "a hand must have exactly 5 cards")
	var counts := {}
	var suits := {}
	for c in cards:
		counts[c.rank] = int(counts.get(c.rank, 0)) + 1
		suits[c.suit] = true
	# groups: [count, rank] sorted by count desc, then rank desc
	var groups: Array = []
	for r in counts:
		groups.append([counts[r], r])
	groups.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] > b[1]))
	var ranks_desc: Array = []
	for g in groups:
		for i in g[0]:
			ranks_desc.append(g[1])

	var is_flush := suits.size() == 1
	var straight_high := _straight_high(counts.keys())
	var category: int
	var tiebreak: Array
	if straight_high > 0 and is_flush:
		category = Category.STRAIGHT_FLUSH
		tiebreak = [straight_high]
	elif groups[0][0] == 4:
		category = Category.FOUR_OF_A_KIND
		tiebreak = [groups[0][1], groups[1][1]]
	elif groups[0][0] == 3 and groups[1][0] == 2:
		category = Category.FULL_HOUSE
		tiebreak = [groups[0][1], groups[1][1]]
	elif is_flush:
		category = Category.FLUSH
		tiebreak = ranks_desc
	elif straight_high > 0:
		category = Category.STRAIGHT
		tiebreak = [straight_high]
	elif groups[0][0] == 3:
		category = Category.THREE_OF_A_KIND
		tiebreak = [groups[0][1], groups[1][1], groups[2][1]]
	elif groups[0][0] == 2 and groups[1][0] == 2:
		category = Category.TWO_PAIR
		tiebreak = [groups[0][1], groups[1][1], groups[2][1]]
	elif groups[0][0] == 2:
		category = Category.ONE_PAIR
		tiebreak = [groups[0][1], groups[1][1], groups[2][1], groups[3][1]]
	else:
		category = Category.HIGH_CARD
		tiebreak = ranks_desc
	return {"category": category, "tiebreak": tiebreak, "name": describe(category, tiebreak)}


## 1 if `a` beats `b`, -1 if `b` beats `a`, 0 for a draw.
static func compare(a: Dictionary, b: Dictionary) -> int:
	if a["category"] != b["category"]:
		return 1 if a["category"] > b["category"] else -1
	var ta: Array = a["tiebreak"]
	var tb: Array = b["tiebreak"]
	for i in mini(ta.size(), tb.size()):
		if ta[i] != tb[i]:
			return 1 if ta[i] > tb[i] else -1
	return 0


static func describe(category: int, tiebreak: Array) -> String:
	var r := func(i: int) -> String: return Card.rank_text(tiebreak[i])
	match category:
		Category.STRAIGHT_FLUSH:
			if tiebreak[0] == 14:
				return "로열 스트레이트 플러시"
			return "스트레이트 플러시 (%s 하이)" % r.call(0)
		Category.FOUR_OF_A_KIND:
			return "포카드 (%s)" % r.call(0)
		Category.FULL_HOUSE:
			return "풀하우스 (%s, %s)" % [r.call(0), r.call(1)]
		Category.FLUSH:
			return "플러시 (%s 하이)" % r.call(0)
		Category.STRAIGHT:
			return "스트레이트 (%s 하이)" % r.call(0)
		Category.THREE_OF_A_KIND:
			return "트리플 (%s)" % r.call(0)
		Category.TWO_PAIR:
			return "투페어 (%s, %s)" % [r.call(0), r.call(1)]
		Category.ONE_PAIR:
			return "원페어 (%s)" % r.call(0)
	return "하이카드 (%s)" % r.call(0)


static func _straight_high(distinct_ranks: Array) -> int:
	if distinct_ranks.size() != 5:
		return 0
	var ranks := distinct_ranks.duplicate()
	ranks.sort()
	if ranks[4] - ranks[0] == 4:
		return ranks[4]
	if ranks == [2, 3, 4, 5, 14]:
		return 5
	return 0
