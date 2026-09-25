class_name GameState
extends RefCounted
## All persistent progress of one save slot. SaveSystem writes it as JSON via to_dict().

const SAVE_VERSION := 3

var player_name := "여행자"
## Single in-game currency. Never negative; every change is recorded in chips_ledger.
var chips_balance := 0
var chips_ledger: Array = []
## Named story/progress flags, e.g. intro_met_lumi, lumi_lamp_reaction_seen.
var flags := {}
var poker_hands_completed := 0
var poker_record := {"win": 0, "draw": 0, "lose": 0, "fold": 0}
## Stake already taken from the balance for a hand that has not been settled yet.
## Non-zero exactly while a hand is in progress; the hand itself is in poker_in_progress.
var pending_poker_stake := 0
## PokerMatch.to_dict() of the unfinished hand, or empty. Restored on load (Design Review 03, D2).
var poker_in_progress := {}
## "day" or "evening". Changes only through player actions (rest, waiting for the gathering).
var time_of_day := "day"
## quest_id -> "active" | "completed". Missing = not started.
var quests := {}
var jobs_completed := 0
## item_id -> count held in storage (not placed).
var owned_items := {}
## Item ids the player has ever obtained (collection book).
var collection: Array = []
## [{"slot": slot_id, "item": item_id}] in the player's home.
var home_placements: Array = []
var current_scene := "village_square"
var player_position := Vector2.ZERO
var has_player_position := false


# --- chips -------------------------------------------------------------------

func add_chips(amount: int, reason: String) -> void:
	assert(amount >= 0, "use spend_chips for negative changes")
	if amount <= 0:
		return
	chips_balance += amount
	_log(amount, reason)


## Returns false and changes nothing when the balance is too low.
func spend_chips(amount: int, reason: String) -> bool:
	if amount < 0 or amount > chips_balance:
		return false
	if amount == 0:
		return true
	chips_balance -= amount
	_log(-amount, reason)
	return true


func _log(delta: int, reason: String) -> void:
	chips_ledger.append({
		"seq": chips_ledger.size() + 1,
		"delta": delta,
		"reason": reason,
		"balance": chips_balance,
	})


# --- flags -------------------------------------------------------------------

func get_flag(flag_name: String) -> bool:
	return bool(flags.get(flag_name, false))


func set_flag(flag_name: String, value: bool = true) -> void:
	flags[flag_name] = value


# --- items and home ----------------------------------------------------------

func owned_count(item_id: String) -> int:
	return int(owned_items.get(item_id, 0))


func grant_item(item_id: String, count: int = 1) -> void:
	owned_items[item_id] = owned_count(item_id) + count
	if not collection.has(item_id):
		collection.append(item_id)


func purchase(item_id: String, price: int) -> bool:
	if not spend_chips(price, "buy:" + item_id):
		return false
	grant_item(item_id)
	return true


func placement_at(slot_id: String) -> String:
	for p in home_placements:
		if p["slot"] == slot_id:
			return p["item"]
	return ""


func is_item_placed(item_id: String) -> bool:
	for p in home_placements:
		if p["item"] == item_id:
			return true
	return false


## Moves one item from storage into an empty slot.
func place_item(slot_id: String, item_id: String) -> bool:
	if placement_at(slot_id) != "" or owned_count(item_id) <= 0:
		return false
	_take_from_storage(item_id)
	home_placements.append({"slot": slot_id, "item": item_id})
	return true


## Moves the item in `slot_id` back to storage.
func remove_placement(slot_id: String) -> bool:
	for i in home_placements.size():
		if home_placements[i]["slot"] == slot_id:
			var item_id: String = home_placements[i]["item"]
			home_placements.remove_at(i)
			owned_items[item_id] = owned_count(item_id) + 1
			return true
	return false


func _take_from_storage(item_id: String) -> void:
	var left := owned_count(item_id) - 1
	if left > 0:
		owned_items[item_id] = left
	else:
		owned_items.erase(item_id)


# --- serialization -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"player_name": player_name,
		"chips_balance": chips_balance,
		"chips_ledger": chips_ledger.duplicate(true),
		"flags": flags.duplicate(),
		"poker_hands_completed": poker_hands_completed,
		"poker_record": poker_record.duplicate(),
		"pending_poker_stake": pending_poker_stake,
		"poker_in_progress": poker_in_progress.duplicate(true),
		"time_of_day": time_of_day,
		"quests": quests.duplicate(),
		"jobs_completed": jobs_completed,
		"owned_items": owned_items.duplicate(),
		"collection": collection.duplicate(),
		"home_placements": home_placements.duplicate(true),
		"current_scene": current_scene,
		"player_position": [player_position.x, player_position.y] if has_player_position else null,
	}


## Builds a state from a dictionary that is already at SAVE_VERSION. JSON numbers arrive as floats.
static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.player_name = str(d.get("player_name", s.player_name))
	s.chips_balance = maxi(0, int(d.get("chips_balance", 0)))
	for e in d.get("chips_ledger", []):
		s.chips_ledger.append({
			"seq": int(e.get("seq", 0)),
			"delta": int(e.get("delta", 0)),
			"reason": str(e.get("reason", "")),
			"balance": int(e.get("balance", 0)),
		})
	var f: Dictionary = d.get("flags", {})
	for k in f:
		s.flags[str(k)] = bool(f[k])
	s.poker_hands_completed = int(d.get("poker_hands_completed", 0))
	var rec: Dictionary = d.get("poker_record", {})
	for k in s.poker_record:
		s.poker_record[k] = int(rec.get(k, 0))
	s.pending_poker_stake = maxi(0, int(d.get("pending_poker_stake", 0)))
	var hand = d.get("poker_in_progress", {})
	if hand is Dictionary and not hand.is_empty():
		# Normalise through PokerMatch (JSON numbers arrive as floats). An unrestorable hand is kept
		# as-is so SaveSystem can report the save as damaged.
		var m := PokerMatch.from_dict(hand)
		s.poker_in_progress = m.to_dict() if m != null else hand.duplicate(true)
	s.time_of_day = "evening" if str(d.get("time_of_day", "day")) == "evening" else "day"
	var q: Dictionary = d.get("quests", {})
	for k in q:
		s.quests[str(k)] = str(q[k])
	s.jobs_completed = int(d.get("jobs_completed", 0))
	var owned: Dictionary = d.get("owned_items", {})
	for k in owned:
		if int(owned[k]) > 0:
			s.owned_items[str(k)] = int(owned[k])
	for id in d.get("collection", []):
		s.collection.append(str(id))
	for p in d.get("home_placements", []):
		s.home_placements.append({"slot": str(p["slot"]), "item": str(p["item"])})
	s.current_scene = str(d.get("current_scene", s.current_scene))
	var pos = d.get("player_position", null)
	if pos is Array and pos.size() == 2:
		s.player_position = Vector2(float(pos[0]), float(pos[1]))
		s.has_player_position = true
	return s
