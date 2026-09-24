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
## Set by PokerRewards.settle so a finished hand is paid out exactly once.
var settled := false
var _ability_uses := {}


func _init(p_deck: Deck, p_max_discards: int = 3, hand_size: int = 5) -> void:
	deck = p_deck
	max_discards = p_max_discards
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
	return result


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
