class_name PokerRewards
extends RefCounted
## Pays out a finished poker hand. Amounts come from data/poker.json "economy".


static func outcome_key(outcome: int) -> String:
	if outcome > 0:
		return "win"
	if outcome < 0:
		return "lose"
	return "draw"


## Applies the result of a finished hand to `state` exactly once.
## Returns {"ok": false} if the hand is unfinished or already settled.
static func settle(state: GameState, m: PokerMatch, economy: Dictionary) -> Dictionary:
	if m.settled or m.phase != PokerMatch.Phase.SHOWDOWN:
		return {"ok": false}
	m.settled = true
	var key := outcome_key(m.outcome)
	var base := int(economy.get("reward_" + key, 0))
	state.add_chips(base, "poker_" + key)
	var bonus := 0
	if not state.get_flag("first_poker_bonus_claimed"):
		bonus = int(economy.get("first_play_bonus", 0))
		state.add_chips(bonus, "first_poker_bonus")
		state.set_flag("first_poker_bonus_claimed")
	state.poker_hands_completed += 1
	state.poker_record[key] = int(state.poker_record.get(key, 0)) + 1
	return {"ok": true, "outcome": key, "base": base, "bonus": bonus, "balance": state.chips_balance}
