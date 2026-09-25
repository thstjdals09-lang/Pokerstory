class_name PokerEconomy
extends RefCounted
## Fixed-stake settlement (Economy v0.2.1, docs/design/Project20_Economy_v0.2.1.md).
## The player and the opponent each put in `stake`; the winner takes the pot.
## The player's stake leaves the balance when the hand starts and is tracked in
## GameState.pending_poker_stake until the hand is settled or folded, so a chip is never
## paid twice and never disappears without a ledger entry. An interrupted hand is not
## refunded: it is saved and resumed (Design Review 03, D2).
## Amounts come from data/poker.json "economy": stake, payout_win, payout_draw, payout_lose.


static func outcome_key(outcome: int) -> String:
	if outcome > 0:
		return "win"
	if outcome < 0:
		return "lose"
	return "draw"


static func stake(economy: Dictionary) -> int:
	return int(economy.get("stake", 0))


static func can_join(state: GameState, economy: Dictionary) -> bool:
	return state.pending_poker_stake == 0 and state.chips_balance >= stake(economy)


## Takes the stake for a new hand. Returns false and changes nothing if the player cannot join.
static func place_stake(state: GameState, economy: Dictionary) -> bool:
	if not can_join(state, economy):
		return false
	var s := stake(economy)
	state.spend_chips(s, "poker_stake")
	state.pending_poker_stake = s
	return true


## Pays out a finished hand exactly once: win returns the whole pot, draw returns the stake,
## loss returns nothing.
static func settle(state: GameState, m: PokerMatch, economy: Dictionary) -> Dictionary:
	if m.settled or m.phase != PokerMatch.Phase.SHOWDOWN or state.pending_poker_stake <= 0:
		return {"ok": false}
	m.settled = true
	var key := outcome_key(m.outcome)
	var payout := int(economy.get("payout_" + key, 0))
	var paid_in := state.pending_poker_stake
	state.pending_poker_stake = 0
	state.add_chips(payout, "poker_payout_" + key)
	state.poker_hands_completed += 1
	state.poker_record[key] = int(state.poker_record.get(key, 0)) + 1
	return {
		"ok": true, "outcome": key, "stake": paid_in, "payout": payout,
		"net": payout - paid_in, "balance": state.chips_balance,
	}


## The player leaves before the showdown: the hand counts as folded and the stake stays lost.
static func fold(state: GameState, m: PokerMatch) -> Dictionary:
	if m.settled or m.phase != PokerMatch.Phase.DRAW or state.pending_poker_stake <= 0:
		return {"ok": false}
	m.settled = true
	var paid_in := state.pending_poker_stake
	state.pending_poker_stake = 0
	state.poker_record["fold"] = int(state.poker_record.get("fold", 0)) + 1
	return {"ok": true, "stake": paid_in}

