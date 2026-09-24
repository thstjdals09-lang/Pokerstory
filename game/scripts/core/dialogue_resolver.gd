class_name DialogueResolver
extends RefCounted
## Picks which dialogue entry an NPC says. Entries are checked in data order;
## the first one whose npc and conditions match wins. ref_only entries are skipped here
## and are reached only through a "dialogue" choice.


static func resolve(entries: Array, npc_id: String, location: String, state: GameState) -> Dictionary:
	for e in entries:
		if e.get("npc", "") != npc_id or e.get("ref_only", false):
			continue
		if Conditions.check(e.get("conditions", {}), state, location):
			return e
	return {}


static func find(entries: Array, entry_id: String) -> Dictionary:
	for e in entries:
		if e.get("id", "") == entry_id:
			return e
	return {}


## Replaces {key} placeholders with values from `vars`.
static func format_line(line: String, vars: Dictionary) -> String:
	var out := line
	for k in vars:
		out = out.replace("{" + str(k) + "}", str(vars[k]))
	return out
