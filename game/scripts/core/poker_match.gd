class_name PokerMatch
extends RefCounted
## One hand of 5-card single-draw poker: the player against one opponent.
## Flow: deal 5 each -> (optional ability) -> player replaces up to max_discards once
## -> opponent replaces by its public rule -> showdown.

enum Phase { DRAW, SHOWDOWN }

var phase: int = Phase.DRAW
var deck: Deck
var max_discards := 3
var player_hand: Array = []
var opponent_hand: Array = []
var player_discards: Array = []
var opponent_discards: Array = []
var player_eval := {}
var opponent_eval := {}
## 1 = player wins, 0 = draw, -1 = player loses. Valid only in SHOWDOWN.
var outcome := 0
## Set by PokerEconomy.settle or fold so a hand is resolved exactly once.
var settled := false
var _ability_uses := {}
## ability_id -> last result, so an interrupted hand shows what the player already learned.
var ability_results := {}
## Content v0.3: which table this is (practice, homegame, social_mix, friendly_challenge,
## tournament), who sits opposite, the one ability taken to the table, the stake paid for this
## hand (0 in practice) and a card the player marked so it cannot be replaced by mistake.
var mode := "homegame"
var opponent_id := ""
var persona := "steady"
var ability_id := ""
var stake := 0
var locked_index := -1
## Where the hand was dealt (a tea-house social game bonds Rira and Taeo, 06_integration/01 #10).
var place := ""


## Deals a new hand from `p_deck`. Pass null to build an empty match (used by from_dict).
func _init(p_deck: Deck = null, p_max_discards: int = 3, hand_size: int = 5) -> void:
	deck = p_deck
	max_discards = p_max_discards
	if deck == null:
		return
	for i in hand_size:
		player_hand.append(deck.draw_one())
		opponent_hand.append(deck.draw_one())


func current_player_eval() -> Dictionary:
	return HandEvaluator.evaluate(player_hand)


func can_use_ability(ability: Dictionary) -> bool:
	if ability.is_empty() or phase != Phase.DRAW:
		return false
	return int(_ability_uses.get(ability["id"], 0)) < int(ability.get("uses_per_match", 1))


## Applies an ability. `context` carries only public information: the table history of this
## opponent (discard counts and hands shown at earlier showdowns) and, for lucky_mark, the card
## index the player chose. Returns {"ok": bool, ...effect-specific fields}.
func use_ability(ability: Dictionary, context: Dictionary = {}) -> Dictionary:
	if not can_use_ability(ability):
		return {"ok": false, "reason": "unavailable"}
	var result := {"ok": true, "effect": str(ability.get("effect", ""))}
	match str(ability.get("effect", "")):
		"reveal_opponent_pair_or_better":
			# Reveals one yes/no fact about the opponent's current hand, never the cards.
			var category: int = HandEvaluator.evaluate(opponent_hand)["category"]
			result["pair_or_better"] = category >= HandEvaluator.Category.ONE_PAIR
		"own_suit_count":
			var counts := {}
			for c in player_hand:
				counts[c.suit] = int(counts.get(c.suit, 0)) + 1
			var best := -1
			for suit in counts:
				if best < 0 or counts[suit] > counts[best] or (counts[suit] == counts[best] and suit < best):
					best = suit
			result["suit"] = player_hand[0].suit_symbol() if best < 0 else _suit_symbol(best)
			result["count"] = int(counts.get(best, 0))
		"discard_hint":
			# From the player's own cards only: which cards make the current hand.
			var keep := _made_cards(player_hand)
			result["keep"] = keep
			result["hand"] = str(HandEvaluator.evaluate(player_hand)["name"])
		"undo_selection":
			result["undo"] = true
		"opponent_last_discards":
			var hist: Array = context.get("history", [])
			result["known"] = not hist.is_empty()
			result["discards"] = int(hist[hist.size() - 1].get("discards", 0)) if not hist.is_empty() else -1
		"lock_card":
			var i := int(context.get("index", -1))
			if i < 0 or i >= player_hand.size():
				return {"ok": false, "reason": "no_card"}
			locked_index = i
			result["index"] = i
		"opponent_pattern":
			var hist: Array = context.get("history", [])
			result["known"] = not hist.is_empty()
			if not hist.is_empty():
				var total := 0
				var cats := {}
				for h in hist:
					total += int(h.get("discards", 0))
					cats[str(h.get("hand", ""))] = int(cats.get(str(h.get("hand", "")), 0)) + 1
				var common := ""
				for k in cats:
					if common == "" or cats[k] > cats[common]:
						common = k
				result["avg_discards"] = snappedf(float(total) / hist.size(), 0.1)
				result["common_hand"] = common
				result["hands_seen"] = hist.size()
		"help_focus":
			result["hand"] = str(HandEvaluator.evaluate(player_hand)["name"])
			result["keep"] = _made_cards(player_hand)
		_:
			return {"ok": false, "reason": "unknown_effect"}
	_ability_uses[ability["id"]] = int(_ability_uses.get(ability["id"], 0)) + 1
	ability_results[ability["id"]] = result.duplicate()
	return result


## Indices of the cards that form the current made hand (pairs, trips, quads, or all five for
## straights and better). Empty for a high-card hand.
static func _made_cards(hand: Array) -> Array:
	var category: int = HandEvaluator.evaluate(hand)["category"]
	if category >= HandEvaluator.Category.STRAIGHT:
		return range(hand.size())
	var counts := {}
	for c in hand:
		counts[c.rank] = int(counts.get(c.rank, 0)) + 1
	var out: Array = []
	for i in hand.size():
		if counts[hand[i].rank] > 1:
			out.append(i)
	return out


static func _suit_symbol(suit: int) -> String:
	return ["♠", "♥", "♦", "♣"][suit] if suit >= 0 and suit < 4 else "?"


# --- persistence (Design Review 03, D2) ----------------------------------------
# A hand in the DRAW phase is saved as it is: both hands, the remaining deck in order,
# and ability use. Restoring it gives exactly the same cards and the same later draws,
# so quitting and restarting cannot change the result.

func to_dict() -> Dictionary:
	return {
		"phase": phase,
		"max_discards": max_discards,
		"player_hand": _codes(player_hand),
		"opponent_hand": _codes(opponent_hand),
		"deck": deck.codes(),
		"deck_seed": deck.seed_used,
		"ability_uses": _ability_uses.duplicate(),
		"ability_results": ability_results.duplicate(true),
		"mode": mode,
		"opponent_id": opponent_id,
		"persona": persona,
		"ability_id": ability_id,
		"stake": stake,
		"locked_index": locked_index,
		"place": place,
	}


## Returns null when the data is not a valid unfinished hand.
static func from_dict(d: Dictionary) -> PokerMatch:
	if int(d.get("phase", -1)) != Phase.DRAW:
		return null
	var m := PokerMatch.new(null, int(d.get("max_discards", 3)))
	m.deck = Deck.from_codes(d.get("deck", []))
	if m.deck == null:
		return null
	m.deck.seed_used = int(d.get("deck_seed", 0))
	var seen := {}
	for c in m.deck.codes():
		seen[c] = true
	for pair in [[d.get("player_hand", []), m.player_hand], [d.get("opponent_hand", []), m.opponent_hand]]:
		if (pair[0] as Array).size() != 5:
			return null
		for code in pair[0]:
			var card := Card.from_code(str(code))
			if card == null or seen.has(card.code()):
				return null
			seen[card.code()] = true
			pair[1].append(card)
	if seen.size() != 52:
		return null
	var uses: Dictionary = d.get("ability_uses", {})
	for k in uses:
		m._ability_uses[str(k)] = int(uses[k])
	var results: Dictionary = d.get("ability_results", {})
	for k in results:
		m.ability_results[str(k)] = results[k]
	# Hands saved before content v0.3 are the card-room home game against the first opponent.
	m.mode = str(d.get("mode", "homegame"))
	m.opponent_id = str(d.get("opponent_id", ""))
	m.persona = str(d.get("persona", "steady"))
	m.ability_id = str(d.get("ability_id", ""))
	m.stake = int(d.get("stake", -1))
	m.locked_index = int(d.get("locked_index", -1))
	m.place = str(d.get("place", ""))
	return m


static func _codes(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(c.code())
	return out


## The player replaces the cards at `indices` (may be empty), then the opponent draws,
## then the hands are compared. Returns false and changes nothing if the request is invalid.
func player_draw(indices: Array) -> bool:
	if phase != Phase.DRAW or indices.size() > max_discards:
		return false
	var seen := {}
	for i in indices:
		if typeof(i) != TYPE_INT or i < 0 or i >= player_hand.size() or seen.has(i) or i == locked_index:
			return false
		seen[i] = true
	player_discards = indices.duplicate()
	player_discards.sort()
	for i in player_discards:
		player_hand[i] = deck.draw_one()
	# The opponent only sees a copy of its own hand.
	opponent_discards = PokerAI.choose_discards(opponent_hand.duplicate(), max_discards, persona)
	for i in opponent_discards:
		opponent_hand[i] = deck.draw_one()
	player_eval = HandEvaluator.evaluate(player_hand)
	opponent_eval = HandEvaluator.evaluate(opponent_hand)
	outcome = HandEvaluator.compare(player_eval, opponent_eval)
	phase = Phase.SHOWDOWN
	return true
