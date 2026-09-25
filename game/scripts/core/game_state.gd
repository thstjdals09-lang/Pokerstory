class_name GameState
extends RefCounted
## All persistent progress of one save slot. SaveSystem writes it as JSON via to_dict().

const SAVE_VERSION := 6

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

# --- content v0.3 (save v4) ---------------------------------------------------
## npc_id -> {met, friendship 0..100, rivalry 0..100, poker_hands, memories[], romance{consent, stage, seen_dates[]}}
var relations := {}
## Registered resident pair_id -> "neutral" | "bonded" | "strained" | "reconciled".
var npc_edges := {}
## project_id -> "complete"
var projects := {}
## 0 starter, 1 cozy, 2 roomy, 3 gathering
var home_stage := 0
## Idempotency keys of one-time events and rewards (dialogue events, scenes, payouts).
var events_done := {}
## Unique activity ids counted toward the act 3 festival.
var contributions: Array = []
## category -> item id for clothing / card_back / chip_style
var equipped := {}
## Abilities the player can pick for a hand.
var abilities_unlocked: Array = ["ability.star_sense"]
## npc_id -> last public hands [{discards, category}] (only what was revealed at showdown).
var poker_history := {}
## Festival tournament: stage 0..3 (3 = won), rewarded flag.
var tournament := {"stage": 0, "rewarded": false}
var tracked_quest := ""
## Mornings since the start (content alpha): varies where residents spend their time.
var day_count := 0
## flag -> day_count when it first turned on (greybox feature complete): "a day later" gates.
var flag_days := {}


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
	if value and not flag_days.has(flag_name) and not bool(flags.get(flag_name, false)):
		flag_days[flag_name] = day_count
	flags[flag_name] = value


# --- residents, projects, events ---------------------------------------------

func relation(npc_id: String) -> Dictionary:
	if not relations.has(npc_id):
		relations[npc_id] = {
			"met": false, "friendship": 0, "rivalry": 0, "poker_hands": 0, "memories": [], "poker_talked": 0,
			"romance": {"consent": false, "stage": "closed", "seen_dates": []},
		}
	return relations[npc_id]


func has_met(npc_id: String) -> bool:
	return relations.has(npc_id) and bool(relations[npc_id]["met"])


func residents_met() -> int:
	var n := 0
	for id in relations:
		n += 1 if relations[id]["met"] else 0
	return n


func edge_phase(pair_id: String) -> String:
	return str(npc_edges.get(pair_id, "neutral"))


func project_done(project_id: String) -> bool:
	return projects.get(project_id, "") == "complete"


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
		"relations": relations.duplicate(true),
		"npc_edges": npc_edges.duplicate(),
		"projects": projects.duplicate(),
		"home_stage": home_stage,
		"events_done": events_done.duplicate(),
		"contributions": contributions.duplicate(),
		"equipped": equipped.duplicate(),
		"abilities_unlocked": abilities_unlocked.duplicate(),
		"poker_history": poker_history.duplicate(true),
		"tournament": tournament.duplicate(),
		"tracked_quest": tracked_quest,
		"day_count": day_count,
		"flag_days": flag_days.duplicate(),
	}


## Puts this state back to a snapshot taken with to_dict() (StateTransaction rollback). The object
## stays the same, so everything holding Game.state sees the restored values.
func restore(d: Dictionary) -> void:
	var fresh := GameState.from_dict(d)
	for prop in get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			set(prop["name"], fresh.get(prop["name"]))


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
	var rels: Dictionary = d.get("relations", {})
	for npc in rels:
		var r: Dictionary = s.relation(str(npc))
		var src: Dictionary = rels[npc]
		r["met"] = bool(src.get("met", false))
		r["friendship"] = clampi(int(src.get("friendship", 0)), 0, 100)
		r["rivalry"] = clampi(int(src.get("rivalry", 0)), 0, 100)
		r["poker_hands"] = int(src.get("poker_hands", 0))
		for m in src.get("memories", []):
			r["memories"].append(str(m))
		var rom: Dictionary = src.get("romance", {})
		r["poker_talked"] = int(src.get("poker_talked", 0))
		r["romance"]["consent"] = bool(rom.get("consent", false))
		r["romance"]["stage"] = str(rom.get("stage", "closed"))
		for sd in rom.get("seen_dates", []):
			r["romance"]["seen_dates"].append(str(sd))
	var edges: Dictionary = d.get("npc_edges", {})
	for k in edges:
		s.npc_edges[str(k)] = str(edges[k])
	var projs: Dictionary = d.get("projects", {})
	for k in projs:
		s.projects[str(k)] = str(projs[k])
	s.home_stage = clampi(int(d.get("home_stage", 0)), 0, 3)
	var ev: Dictionary = d.get("events_done", {})
	for k in ev:
		s.events_done[str(k)] = true
	for c in d.get("contributions", []):
		s.contributions.append(str(c))
	var eq: Dictionary = d.get("equipped", {})
	for k in eq:
		s.equipped[str(k)] = str(eq[k])
	if d.has("abilities_unlocked"):
		s.abilities_unlocked = []
		for a in d["abilities_unlocked"]:
			s.abilities_unlocked.append(str(a))
	var hist: Dictionary = d.get("poker_history", {})
	for npc in hist:
		var rows: Array = []
		for h in hist[npc]:
			rows.append({"discards": int(h.get("discards", 0)), "hand": str(h.get("hand", "")), "outcome": str(h.get("outcome", ""))})
		s.poker_history[str(npc)] = rows
	var t: Dictionary = d.get("tournament", {})
	s.tournament = {"stage": clampi(int(t.get("stage", 0)), 0, 3), "rewarded": bool(t.get("rewarded", false))}
	s.tracked_quest = str(d.get("tracked_quest", ""))
	s.day_count = maxi(0, int(d.get("day_count", 0)))
	var fd: Dictionary = d.get("flag_days", {})
	for k in fd:
		s.flag_days[str(k)] = int(fd[k])
	return s
