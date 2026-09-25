class_name DialogueResolver
extends RefCounted
## Picks which dialogue entry a speaker (resident id, or "obj:<id>" for a world object) says.
## Entries are already sorted by priority (DataDB); the first whose speaker and conditions match
## wins. ref_only entries are reached only through a "dialogue" choice. "once" entries are skipped
## after they were shown (GameState.events_done "dlg:<id>").


static func resolve(entries: Array, speaker: String, location: String, state: GameState) -> Dictionary:
	for e in entries:
		if e.get("npc", "") != speaker or e.get("ref_only", false):
			continue
		if e.get("once", false) and state.events_done.has(once_key(e)):
			continue
		if Conditions.check(e.get("conditions", {}), state, location):
			return e
	return {}


static func once_key(entry: Dictionary) -> String:
	return "dlg:" + str(entry.get("id", ""))


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
