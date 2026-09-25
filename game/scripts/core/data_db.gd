class_name DataDB
extends RefCounted
## Loads all game content from JSON files under data/ and checks cross-references
## (content audit, docs/design/content_v0.3/06_integration/06_CONTENT_AUDIT.md).

const DIALOGUE_ACTIONS := [
	"close", "start_poker", "open_shop", "dialogue", "accept_quest", "complete_quest",
	"effects", "fund_project", "upgrade_home", "start_job", "trade", "set_time",
	"quest_offer", "job_deliver", "shelve", "board", "poker_loadout", "wait_and_enter",
]
const TIMES := ["day", "evening"]
const ECONOMY_KEYS := ["starting_chips", "stake", "payout_win", "payout_draw", "payout_lose"]
const ITEM_CATEGORIES := ["furniture", "decor", "clothing", "card_back", "chip_style", "memento"]
const PLACEABLE_CATEGORIES := ["furniture", "decor", "memento"]
const EQUIP_CATEGORIES := ["clothing", "card_back", "chip_style"]
const EDGE_PHASES := ["neutral", "bonded", "strained", "reconciled"]
const ROMANCE_STAGES := ["closed", "eligible", "dating", "committed"]
const EFFECT_TYPES := [
	"flag", "chips", "spend", "meet", "friendship", "rivalry", "memory", "item", "edge", "romance",
	"contribution", "quest_start", "project", "home_stage", "unlock_ability", "equip", "toast",
]

var items := {}
var item_order: Array = []
## Old item id -> current id (content v0.3 aliases; C3 in the implementation log).
var legacy_item_ids := {}
var npcs := {}
var npc_order: Array = []
var dialogue: Array = []
var locations := {}
var places := {}
var shops := {}
var trades: Array = []
var poker := {}
var abilities := {}
var ability_aliases := {}
var opponents := {}
var goals: Array = []
var quests := {}
var quest_order: Array = []
var jobs := {}
var projects := {}
var project_order: Array = []
var home := {}
var edges := {}
var story := {}


## Loads every data file and validates it. Returns a list of error messages (empty = OK).
func load_all(dir: String) -> Array:
	var errors: Array = []
	var items_doc := _read(dir + "/items.json", errors)
	for it in items_doc.get("items", []):
		if items.has(it["id"]):
			errors.append("duplicate item id: %s" % it["id"])
		items[it["id"]] = it
		item_order.append(it["id"])
	legacy_item_ids = items_doc.get("legacy_id_map", {})
	for n in _read(dir + "/npcs.json", errors).get("npcs", []):
		if npcs.has(n["id"]):
			errors.append("duplicate npc id: %s" % n["id"])
		npcs[n["id"]] = n
		npc_order.append(n["id"])
	dialogue = _read(dir + "/dialogue.json", errors).get("entries", [])
	var extra := Array(DirAccess.get_files_at(dir + "/dialogue"))
	extra.sort()
	for f in extra:
		if f.ends_with(".json"):
			dialogue.append_array(_read(dir + "/dialogue/" + f, errors).get("entries", []))
	locations = _read(dir + "/locations.json", errors).get("locations", {})
	places = _read(dir + "/places.json", errors).get("places", {})
	var shops_doc := _read(dir + "/shops.json", errors)
	shops = shops_doc.get("shops", {})
	trades = shops_doc.get("trades", [])
	poker = _read(dir + "/poker.json", errors)
	for a in poker.get("abilities", []):
		abilities[a["id"]] = a
		for alias in a.get("aliases", []):
			ability_aliases[alias] = a["id"]
	for o in poker.get("opponents", []):
		opponents[o["npc"]] = o
	goals = _read(dir + "/goals.json", errors).get("goals", [])
	for q in _read(dir + "/quests.json", errors).get("quests", []):
		quests[q["id"]] = q
		quest_order.append(q["id"])
	for ep in _read(dir + "/episodes.json", errors).get("episodes", []):
		ep["kind"] = "episode"
		quests[ep["id"]] = ep
		quest_order.append(ep["id"])
	for j in _read(dir + "/jobs.json", errors).get("jobs", []):
		jobs[j["id"]] = j
	for p in _read(dir + "/projects.json", errors).get("projects", []):
		projects[p["id"]] = p
		project_order.append(p["id"])
	home = _read(dir + "/home.json", errors)
	for e in _read(dir + "/relations.json", errors).get("edges", []):
		edges[e["id"]] = e
	story = _read(dir + "/story.json", errors)
	# Stable priority order for dialogue: higher priority first, data order within a priority.
	for i in dialogue.size():
		dialogue[i]["_order"] = i
	dialogue.sort_custom(_by_priority)
	if errors.is_empty():
		errors.append_array(validate())
	return errors


static func _by_priority(a: Dictionary, b: Dictionary) -> bool:
	var pa := int(a.get("priority", 50))
	var pb := int(b.get("priority", 50))
	return pa > pb or (pa == pb and int(a["_order"]) < int(b["_order"]))


func item_price(item_id: String) -> int:
	return int(items.get(item_id, {}).get("price", 0))


func npc_name(npc_id: String) -> String:
	return str(npcs.get(npc_id, {}).get("name", npc_id))


func is_quest(id: String) -> bool:
	return quests.has(id) and quests[id].get("kind", "quest") == "quest"


## Where a resident stands at `time`: the first matching override, else the schedule.
## Returns {"loc": location_id, "pos": [x, y], "radius"?: n} or {} (not in any place).
## Exactly one place per resident per moment, by construction (no duplicates).
func npc_place(npc_id: String, time: String, state: GameState) -> Dictionary:
	var def: Dictionary = npcs.get(npc_id, {})
	for o in def.get("overrides", []):
		if o.get("time", time) == time and state != null and Conditions.check(o.get("conditions", {}), state):
			return o
	return def.get("schedule", {}).get(time, {})


## Location ids where `npc_id` can stand at `time` by schedule (overrides replace, never add).
func npc_locations(npc_id: String, time: String) -> Array:
	var p: Dictionary = npcs.get(npc_id, {}).get("schedule", {}).get(time, {})
	return [p["loc"]] if p.has("loc") else []


static func placement_active(placement: Dictionary, time: String) -> bool:
	var t := str(placement.get("time", "any"))
	return t == "any" or t == time


## Cross-reference checks between data files.
func validate() -> Array:
	var errors: Array = []
	var object_ids := {}
	var interactable_ids := {}
	for loc_id in locations:
		for it in locations[loc_id].get("interactables", []):
			if interactable_ids.has(it["id"]):
				errors.append("duplicate interactable id %s" % it["id"])
			interactable_ids[it["id"]] = loc_id
			object_ids["obj:" + str(it["id"])] = true
		for d in locations[loc_id].get("buildings", []) + locations[loc_id].get("exits", []):
			interactable_ids[d.get("id", "")] = loc_id

	var entry_ids := {}
	for e in dialogue:
		var id: String = e.get("id", "")
		if id == "" or entry_ids.has(id):
			errors.append("dialogue entry id missing or duplicated: '%s'" % id)
		entry_ids[id] = true
		var speaker: String = e.get("npc", "")
		if not npcs.has(speaker) and not object_ids.has(speaker):
			errors.append("dialogue %s: unknown speaker %s" % [id, speaker])
		if (e.get("lines", []) as Array).is_empty():
			errors.append("dialogue %s: no lines" % id)
		errors.append_array(_check_conditions(e.get("conditions", {}), "dialogue " + id))
		errors.append_array(_check_effects(e.get("effects", []), "dialogue " + id))
	for e in dialogue:
		for c in e.get("choices", []):
			var action: String = c.get("action", "")
			var where := "dialogue %s choice" % e["id"]
			errors.append_array(_check_conditions(c.get("conditions", {}), where))
			errors.append_array(_check_effects(c.get("effects", []), where))
			if not DIALOGUE_ACTIONS.has(action):
				errors.append("%s: unknown action %s" % [where, action])
			if action in ["accept_quest", "complete_quest"] and not quests.has(c.get("arg", "")):
				errors.append("%s: unknown quest %s" % [where, c.get("arg", "")])
			if action == "dialogue" and not entry_ids.has(c.get("arg", "")):
				errors.append("%s: missing target entry %s" % [where, c.get("arg", "")])
			if action == "open_shop" and not shops.has(c.get("arg", "")):
				errors.append("%s: unknown shop %s" % [where, c.get("arg", "")])
			if c.has("next") and not entry_ids.has(c["next"]):
				errors.append("%s: missing next entry %s" % [where, c["next"]])

	for loc_id in locations:
		var loc: Dictionary = locations[loc_id]
		for key in ["name", "size", "spawns"]:
			if not loc.has(key):
				errors.append("location %s: missing %s" % [loc_id, key])
		if not loc.get("spawns", {}).has("default"):
			errors.append("location %s: missing default spawn" % loc_id)
		var doors: Array = []
		doors.append_array(loc.get("buildings", []))
		doors.append_array(loc.get("exits", []))
		for d in doors:
			var target: String = d.get("target", "")
			if not locations.has(target):
				errors.append("location %s: door to unknown location %s" % [loc_id, target])
			elif not locations[target].get("spawns", {}).has(d.get("spawn", "")):
				errors.append("location %s: door spawn %s missing in %s" % [loc_id, d.get("spawn", ""), target])
			errors.append_array(_check_conditions(d.get("unlock", {}), "door " + str(d.get("id", ""))))
		for deco in loc.get("decor", []):
			if deco.get("type", "") == "item_display" and not items.has(deco.get("item", "")):
				errors.append("location %s: display of unknown item %s" % [loc_id, deco.get("item", "")])
			errors.append_array(_check_conditions(deco.get("conditions", {}), "decor in " + loc_id))
		for it in loc.get("interactables", []):
			errors.append_array(_check_conditions(it.get("conditions", {}), "interactable " + str(it["id"])))
		for s in loc.get("slots", []):
			errors.append_array(_check_conditions(s.get("conditions", {}), "slot " + str(s["id"])))

	# Residents: a schedule place for both times (or explicitly none), valid locations.
	for npc_id in npcs:
		var def: Dictionary = npcs[npc_id]
		for t in TIMES:
			var p: Dictionary = def.get("schedule", {}).get(t, {})
			if p.has("loc") and not locations.has(p["loc"]):
				errors.append("npc %s: %s location %s unknown" % [npc_id, t, p["loc"]])
		for o in def.get("overrides", []):
			if not locations.has(o.get("loc", "")):
				errors.append("npc %s: override location unknown" % npc_id)
			errors.append_array(_check_conditions(o.get("conditions", {}), "npc override " + npc_id))
		if def.get("romance", false) and not def.get("adult", false):
			errors.append("npc %s: romance requires an adult resident" % npc_id)

	for place_id in places:
		var pl: Dictionary = places[place_id]
		if not locations.has(pl.get("scene", "")):
			errors.append("place %s: unknown scene %s" % [place_id, pl.get("scene", "")])
		if not interactable_ids.has(pl.get("entrance", "")) and not pl.get("entrance", "") == "spawn":
			errors.append("place %s: unknown entrance %s" % [place_id, pl.get("entrance", "")])
		errors.append_array(_check_conditions(pl.get("unlock", {}), "place " + place_id))

	for quest_id in quests:
		var q: Dictionary = quests[quest_id]
		if not npcs.has(q.get("giver", "")):
			errors.append("quest %s: unknown giver" % quest_id)
		var target: String = q.get("target", "")
		if not npcs.has(target) and not object_ids.has("obj:" + target):
			errors.append("quest %s: unknown target %s" % [quest_id, target])
		if int(q.get("reward", 0)) < 0:
			errors.append("quest %s: negative reward" % quest_id)
		if q.has("complete_dialogue") and not entry_ids.has(q["complete_dialogue"]):
			errors.append("quest %s: missing complete_dialogue" % quest_id)
		errors.append_array(_check_conditions(q.get("unlock", {}), "quest " + quest_id))
		errors.append_array(_check_effects(q.get("effects", []), "quest " + quest_id))
	for job_id in jobs:
		var j: Dictionary = jobs[job_id]
		if int(j.get("reward", -1)) < 0 or int(j.get("count", 0)) <= 0:
			errors.append("job %s: reward/count missing" % job_id)
		if j.get("type", "collect") == "collect" and (j.get("spots", []) as Array).size() < int(j.get("count", 0)):
			errors.append("job %s: fewer spots than count" % job_id)
		if not locations.has(j.get("location", "")):
			errors.append("job %s: unknown location" % job_id)
		for r in j.get("recipients", []):
			if not npcs.has(r):
				errors.append("job %s: unknown recipient %s" % [job_id, r])
	for pid in projects:
		var p: Dictionary = projects[pid]
		errors.append_array(_check_conditions(p.get("unlock", {}), "project " + pid))
		errors.append_array(_check_effects(p.get("effects", []), "project " + pid))
	for st in home.get("stages", []):
		errors.append_array(_check_conditions(st.get("unlock", {}), "home stage " + str(st.get("id", ""))))

	for shop_id in shops:
		for entry in shops[shop_id].get("items", []):
			var item_id: String = entry if entry is String else entry.get("item", "")
			if not items.has(item_id):
				errors.append("shop %s: unknown item %s" % [shop_id, item_id])
			if entry is Dictionary:
				errors.append_array(_check_conditions(entry.get("unlock", {}), "shop %s item" % shop_id))
		if not npcs.has(shops[shop_id].get("owner", "")):
			errors.append("shop %s: unknown owner" % shop_id)
	for t in trades:
		for key in ["give", "get"]:
			if not items.has(t.get(key, "")):
				errors.append("trade %s: unknown item" % t.get("id", ""))
	for item_id in items:
		if not ITEM_CATEGORIES.has(items[item_id].get("category", "")):
			errors.append("item %s: bad category" % item_id)
	for old in legacy_item_ids:
		if not items.has(legacy_item_ids[old]):
			errors.append("legacy item map %s -> unknown" % old)

	var econ: Dictionary = poker.get("economy", {})
	for key in ECONOMY_KEYS:
		if not econ.has(key) or int(econ[key]) < 0:
			errors.append("poker economy: %s missing or negative" % key)
	if not abilities.has(poker.get("player_ability", "")):
		errors.append("poker: unknown player_ability")
	if not npcs.has(poker.get("rules", {}).get("opponent", "")):
		errors.append("poker: unknown opponent")
	for npc_id in opponents:
		if not npcs.has(npc_id):
			errors.append("poker opponent %s unknown" % npc_id)
	for edge_id in edges:
		for m in edges[edge_id].get("members", []):
			if not npcs.has(m):
				errors.append("edge %s: unknown member %s" % [edge_id, m])

	for g in goals:
		errors.append_array(_check_conditions(g.get("conditions", {}), "goal " + str(g.get("text", ""))))
	return errors


func _check_effects(effects: Array, where: String) -> Array:
	var errors: Array = []
	for e in effects:
		var t: String = e.get("type", "")
		if not EFFECT_TYPES.has(t):
			errors.append("%s: unknown effect %s" % [where, t])
		elif t in ["meet", "friendship", "rivalry", "memory", "romance"] and not npcs.has(e.get("npc", "")):
			errors.append("%s: effect for unknown npc %s" % [where, e.get("npc", "")])
		elif t == "item" and not items.has(e.get("item", "")):
			errors.append("%s: effect for unknown item %s" % [where, e.get("item", "")])
		elif t == "edge" and (not edges.has(e.get("pair", "")) or not EDGE_PHASES.has(e.get("phase", ""))):
			errors.append("%s: bad edge effect %s" % [where, e.get("pair", "")])
		elif t == "romance" and e.has("stage") and not ROMANCE_STAGES.has(e["stage"]):
			errors.append("%s: bad romance stage" % where)
		elif t == "romance" and not npcs.get(e.get("npc", ""), {}).get("romance", false):
			errors.append("%s: romance effect for a non-romance resident %s" % [where, e.get("npc", "")])
		elif t == "quest_start" and not quests.has(e.get("quest", "")):
			errors.append("%s: unknown quest %s" % [where, e.get("quest", "")])
		elif t == "project" and not projects.has(e.get("project", "")):
			errors.append("%s: unknown project %s" % [where, e.get("project", "")])
		elif t == "unlock_ability" and not abilities.has(e.get("ability", "")):
			errors.append("%s: unknown ability %s" % [where, e.get("ability", "")])
	return errors


func _check_conditions(cond: Dictionary, where: String) -> Array:
	var errors: Array = []
	for key in cond:
		var v = cond[key]
		if not Conditions.KNOWN_KEYS.has(key):
			errors.append("%s: unknown condition %s" % [where, key])
		elif key in ["all", "any"]:
			for c in v:
				errors.append_array(_check_conditions(c, where))
		elif key == "not":
			errors.append_array(_check_conditions(v, where))
		elif key in Conditions.ITEM_KEYS and not items.has(v):
			errors.append("%s: unknown item %s" % [where, v])
		elif key in Conditions.QUEST_KEYS and not quests.has(v):
			errors.append("%s: unknown quest %s" % [where, v])
		elif key in Conditions.NPC_KEYS and not npcs.has(v):
			errors.append("%s: unknown npc %s" % [where, v])
		elif key in Conditions.NPC_MAP_KEYS:
			for npc in v:
				if not npcs.has(npc):
					errors.append("%s: unknown npc %s" % [where, npc])
		elif key in Conditions.PROJECT_KEYS and not projects.has(v):
			errors.append("%s: unknown project %s" % [where, v])
		elif key == "edge_phase":
			for pair in v:
				if not edges.has(pair):
					errors.append("%s: unknown edge %s" % [where, pair])
		elif key == "time" and not TIMES.has(v):
			errors.append("%s: unknown time %s" % [where, v])
		elif key == "location" and not locations.has(v):
			errors.append("%s: unknown location %s" % [where, v])
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
