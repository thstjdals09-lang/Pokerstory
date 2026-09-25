class_name DataDB
extends RefCounted
## Loads all game content from JSON files under data/ and checks cross-references.

const DIALOGUE_ACTIONS := ["close", "start_poker", "open_shop", "dialogue", "accept_quest", "complete_quest"]
const TIMES := ["day", "evening"]
const ECONOMY_KEYS := ["starting_chips", "stake", "payout_win", "payout_draw", "payout_lose"]

var items := {}
var item_order: Array = []
var npcs := {}
var dialogue: Array = []
var locations := {}
var shops := {}
var poker := {}
var abilities := {}
var goals: Array = []
var quests := {}
var jobs := {}


## Loads every data file and validates it. Returns a list of error messages (empty = OK).
func load_all(dir: String) -> Array:
	var errors: Array = []
	for it in _read(dir + "/items.json", errors).get("items", []):
		if items.has(it["id"]):
			errors.append("duplicate item id: %s" % it["id"])
		items[it["id"]] = it
		item_order.append(it["id"])
	for n in _read(dir + "/npcs.json", errors).get("npcs", []):
		npcs[n["id"]] = n
	dialogue = _read(dir + "/dialogue.json", errors).get("entries", [])
	locations = _read(dir + "/locations.json", errors).get("locations", {})
	shops = _read(dir + "/shops.json", errors).get("shops", {})
	poker = _read(dir + "/poker.json", errors)
	for a in poker.get("abilities", []):
		abilities[a["id"]] = a
	goals = _read(dir + "/goals.json", errors).get("goals", [])
	for q in _read(dir + "/quests.json", errors).get("quests", []):
		quests[q["id"]] = q
	for j in _read(dir + "/jobs.json", errors).get("jobs", []):
		jobs[j["id"]] = j
	if errors.is_empty():
		errors.append_array(validate())
	return errors


func item_price(item_id: String) -> int:
	return int(items.get(item_id, {}).get("price", 0))


func npc_name(npc_id: String) -> String:
	return str(npcs.get(npc_id, {}).get("name", npc_id))


## True when a placement ("time": "day" | "evening" | "any", default "any") is active at `time`.
static func placement_active(placement: Dictionary, time: String) -> bool:
	var t := str(placement.get("time", "any"))
	return t == "any" or t == time


## Location ids where `npc_id` stands at `time`. Valid data has at most one.
func npc_locations(npc_id: String, time: String) -> Array:
	var out: Array = []
	for loc_id in locations:
		for p in locations[loc_id].get("npcs", []):
			if p["id"] == npc_id and placement_active(p, time):
				out.append(loc_id)
	return out


## Cross-reference checks between data files.
func validate() -> Array:
	var errors: Array = []
	var entry_ids := {}
	for e in dialogue:
		var id: String = e.get("id", "")
		if id == "" or entry_ids.has(id):
			errors.append("dialogue entry id missing or duplicated: '%s'" % id)
		entry_ids[id] = true
		if not npcs.has(e.get("npc", "")):
			errors.append("dialogue %s: unknown npc %s" % [id, e.get("npc", "")])
		if (e.get("lines", []) as Array).is_empty():
			errors.append("dialogue %s: no lines" % id)
		errors.append_array(_check_conditions(e.get("conditions", {}), "dialogue " + id))
	for e in dialogue:
		for c in e.get("choices", []):
			var action: String = c.get("action", "")
			errors.append_array(_check_conditions(c.get("conditions", {}), "dialogue %s choice" % e["id"]))
			if action in ["accept_quest", "complete_quest"] and not quests.has(c.get("arg", "")):
				errors.append("dialogue %s: unknown quest %s" % [e["id"], c.get("arg", "")])
			if not DIALOGUE_ACTIONS.has(action):
				errors.append("dialogue %s: unknown action %s" % [e["id"], action])
			if action == "dialogue" and not entry_ids.has(c.get("arg", "")):
				errors.append("dialogue %s: missing target entry %s" % [e["id"], c.get("arg", "")])
			if action == "open_shop" and not shops.has(c.get("arg", "")):
				errors.append("dialogue %s: unknown shop %s" % [e["id"], c.get("arg", "")])

	for loc_id in locations:
		var loc: Dictionary = locations[loc_id]
		for key in ["name", "size", "spawns"]:
			if not loc.has(key):
				errors.append("location %s: missing %s" % [loc_id, key])
		if not loc.get("spawns", {}).has("default"):
			errors.append("location %s: missing default spawn" % loc_id)
		for n in loc.get("npcs", []):
			if not npcs.has(n["id"]):
				errors.append("location %s: unknown npc %s" % [loc_id, n["id"]])
			if not (str(n.get("time", "any")) in ["any", "day", "evening"]):
				errors.append("location %s: bad time for %s" % [loc_id, n["id"]])
		var doors: Array = []
		doors.append_array(loc.get("buildings", []))
		doors.append_array(loc.get("exits", []))
		for d in doors:
			var target: String = d.get("target", "")
			if not locations.has(target):
				errors.append("location %s: door to unknown location %s" % [loc_id, target])
			elif not locations[target].get("spawns", {}).has(d.get("spawn", "")):
				errors.append("location %s: door spawn %s missing in %s" % [loc_id, d.get("spawn", ""), target])
		for deco in loc.get("decor", []):
			if deco.get("type", "") == "item_display" and not items.has(deco.get("item", "")):
				errors.append("location %s: display of unknown item %s" % [loc_id, deco.get("item", "")])

	# A resident stands in at most one place at any time of day.
	for npc_id in npcs:
		for t in TIMES:
			var where := npc_locations(npc_id, t)
			if where.size() > 1:
				errors.append("npc %s is in %s at the same time (%s)" % [npc_id, str(where), t])

	for quest_id in quests:
		var q: Dictionary = quests[quest_id]
		for key in ["giver", "target"]:
			if not npcs.has(q.get(key, "")):
				errors.append("quest %s: unknown %s" % [quest_id, key])
		if int(q.get("reward", -1)) < 0:
			errors.append("quest %s: reward missing" % quest_id)
		if q.has("complete_dialogue") and not entry_ids.has(q["complete_dialogue"]):
			errors.append("quest %s: missing complete_dialogue" % quest_id)
	for job_id in jobs:
		var j: Dictionary = jobs[job_id]
		if int(j.get("reward", -1)) < 0 or int(j.get("count", 0)) <= 0:
			errors.append("job %s: reward/count missing" % job_id)
		if (j.get("spots", []) as Array).size() < int(j.get("count", 0)):
			errors.append("job %s: fewer spots than count" % job_id)
		if not locations.has(j.get("location", "")):
			errors.append("job %s: unknown location" % job_id)

	for shop_id in shops:
		for item_id in shops[shop_id].get("items", []):
			if not items.has(item_id):
				errors.append("shop %s: unknown item %s" % [shop_id, item_id])
		if not npcs.has(shops[shop_id].get("owner", "")):
			errors.append("shop %s: unknown owner" % shop_id)

	var econ: Dictionary = poker.get("economy", {})
	for key in ECONOMY_KEYS:
		if not econ.has(key) or int(econ[key]) < 0:
			errors.append("poker economy: %s missing or negative" % key)
	if not abilities.has(poker.get("player_ability", "")):
		errors.append("poker: unknown player_ability")
	if not npcs.has(poker.get("rules", {}).get("opponent", "")):
		errors.append("poker: unknown opponent")

	for g in goals:
		errors.append_array(_check_conditions(g.get("conditions", {}), "goal " + str(g.get("text", ""))))
	return errors


func _check_conditions(cond: Dictionary, where: String) -> Array:
	var errors: Array = []
	for key in cond:
		if not Conditions.KNOWN_KEYS.has(key):
			errors.append("%s: unknown condition %s" % [where, key])
		elif key in Conditions.ITEM_KEYS and not items.has(cond[key]):
			errors.append("%s: unknown item %s" % [where, cond[key]])
		elif key in Conditions.QUEST_KEYS and not quests.has(cond[key]):
			errors.append("%s: unknown quest %s" % [where, cond[key]])
		elif key == "time" and not TIMES.has(cond[key]):
			errors.append("%s: unknown time %s" % [where, cond[key]])
		elif key == "location" and not locations.has(cond[key]):
			errors.append("%s: unknown location %s" % [where, cond[key]])
	return errors


static func _read(path: String, errors: Array) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("missing data file: " + path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("invalid JSON: " + path)
		return {}
	return parsed
