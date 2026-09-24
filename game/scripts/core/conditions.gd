class_name Conditions
extends RefCounted
## Evaluates data-defined conditions (dialogue entries, goals) against the game state.
## Every key present must hold. An empty dictionary always matches.

const KNOWN_KEYS := [
	"flags_true", "flags_false",
	"placed_item", "not_placed_item",
	"owns_or_placed_item", "not_owned_or_placed",
	"min_poker_hands", "max_poker_hands",
	"location",
]


static func check(cond: Dictionary, state: GameState, location: String = "") -> bool:
	for key in cond:
		var v = cond[key]
		match key:
			"flags_true":
				for f in v:
					if not state.get_flag(f):
						return false
			"flags_false":
				for f in v:
					if state.get_flag(f):
						return false
			"placed_item":
				if not state.is_item_placed(v):
					return false
			"not_placed_item":
				if state.is_item_placed(v):
					return false
			"owns_or_placed_item":
				if state.owned_count(v) <= 0 and not state.is_item_placed(v):
					return false
			"not_owned_or_placed":
				if state.owned_count(v) > 0 or state.is_item_placed(v):
					return false
			"min_poker_hands":
				if state.poker_hands_completed < int(v):
					return false
			"max_poker_hands":
				if state.poker_hands_completed > int(v):
					return false
			"location":
				if location != v:
					return false
			_:
				push_error("Unknown condition key: %s" % key)
				return false
	return true
