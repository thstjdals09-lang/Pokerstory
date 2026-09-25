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


## Applies an ability. Returns {"ok": bool, ...effect-specific fields}.
func use_ability(ability: Dictionary) -> Dictionary:
	if not can_use_ability(ability):
		return {"ok": false, "reason": "unavailable"}
	var result := {"ok": true}
	match str(ability.get("effect", "")):
		"reveal_opponent_pair_or_better":
			# Reveals one yes/no fact about the opponent's current hand, never the cards.
			var category: int = HandEvaluator.evaluate(opponent_hand)["category"]
			result["pair_or_better"] = category >= HandEvaluator.Category.ONE_PAIR
		_:
			return {"ok": false, "reason": "unknown_effect"}
	_ability_uses[ability["id"]] = int(_ability_uses.get(ability["id"], 0)) + 1
	ability_results[ability["id"]] = result.duplicate()
	return result


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
		if typeof(i) != TYPE_INT or i < 0 or i >= player_hand.size() or seen.has(i):
			return false
		seen[i] = true
	player_discards = indices.duplicate()
	player_discards.sort()
	for i in player_discards:
		player_hand[i] = deck.draw_one()
	# The opponent only sees a copy of its own hand.
	opponent_discards = PokerAI.choose_discards(opponent_hand.duplicate(), max_discards)
	for i in opponent_discards:
		opponent_hand[i] = deck.draw_one()
	player_eval = HandEvaluator.evaluate(player_hand)
	opponent_eval = HandEvaluator.evaluate(opponent_hand)
	outcome = HandEvaluator.compare(player_eval, opponent_eval)
	phase = Phase.SHOWDOWN
	return true
