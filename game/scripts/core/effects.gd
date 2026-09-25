class_name Effects
extends RefCounted
## Applies data-defined effects (dialogue events, scenes, quests, projects, objects) to the state.
## A list runs all-or-nothing: chip costs are checked before anything changes. When a `key` is given
## the list runs at most once per save (the key is stored in GameState.events_done), so replaying a
## scene or reopening a dialogue never pays twice.
##
## Effect types:
##   flag {flag, value=true}           chips {amount, reason}          spend {amount, reason}
##   meet {npc}                         friendship {npc, amount}        rivalry {npc, amount}
##   memory {npc, id}                   item {item, count=1}            edge {pair, phase}
##   romance {npc, stage?, consent?, date?}                             contribution {id}
##   quest_start {quest}                project {project}               home_stage {stage}
##   unlock_ability {ability}           equip {category, item}          toast {text}
## Any single effect may carry "once": <key>; it is then applied at most once per save even when
## different scenes grant it (e.g. the festival helper memento on the first and later festivals).

const REL_MAX := 100


## Returns {"ok": bool, "skipped": bool, "reason": String, "messages": [String]}.
static func apply(state: GameState, effects: Array, key: String = "") -> Dictionary:
	if key != "" and state.events_done.has(key):
		return {"ok": true, "skipped": true, "messages": []}
	var cost := 0
	for e in effects:
		if e.get("type", "") == "spend":
			cost += int(e.get("amount", 0))
	if cost > state.chips_balance:
		return {"ok": false, "skipped": false, "reason": "not_enough_chips", "need": cost - state.chips_balance, "messages": []}
	var messages: Array = []
	for e in effects:
		var once := str(e.get("once", ""))
		if once != "":
			if state.events_done.has(once):
				continue
			state.events_done[once] = true
		_apply_one(state, e, messages)
	if key != "":
		state.events_done[key] = true
	return {"ok": true, "skipped": false, "messages": messages}


static func _apply_one(state: GameState, e: Dictionary, messages: Array) -> void:
	match str(e.get("type", "")):
		"flag":
			state.set_flag(str(e["flag"]), bool(e.get("value", true)))
		"chips":
			state.add_chips(int(e["amount"]), str(e.get("reason", "event")))
		"spend":
			state.spend_chips(int(e["amount"]), str(e.get("reason", "event")))
		"meet":
			var r := state.relation(str(e["npc"]))
			if not r["met"]:
				r["met"] = true
				r["friendship"] = mini(REL_MAX, int(r["friendship"]) + 5)
		"friendship":
			var r := state.relation(str(e["npc"]))
			r["friendship"] = clampi(int(r["friendship"]) + int(e["amount"]), 0, REL_MAX)
		"rivalry":
			var r := state.relation(str(e["npc"]))
			r["rivalry"] = clampi(int(r["rivalry"]) + int(e["amount"]), 0, REL_MAX)
		"memory":
			var r := state.relation(str(e["npc"]))
			if not r["memories"].has(e["id"]):
				r["memories"].append(str(e["id"]))
		"item":
			state.grant_item(str(e["item"]), int(e.get("count", 1)))
		"edge":
			state.npc_edges[str(e["pair"])] = str(e["phase"])
		"romance":
			var rom: Dictionary = state.relation(str(e["npc"]))["romance"]
			if e.has("consent"):
				rom["consent"] = bool(e["consent"])
			if e.has("stage"):
				rom["stage"] = str(e["stage"])
			if e.has("date") and not rom["seen_dates"].has(e["date"]):
				rom["seen_dates"].append(str(e["date"]))
		"contribution":
			# Counts only while the festival is being prepared (act 3), once per activity id.
			var id := str(e["id"])
			if state.get_flag("story.act3_started") and not state.get_flag("story.festival_ready") \
					and not state.contributions.has(id):
				state.contributions.append(id)
		"quest_start":
			QuestBook.accept(state, str(e["quest"]))
		"project":
			state.projects[str(e["project"])] = "complete"
		"home_stage":
			state.home_stage = maxi(state.home_stage, int(e["stage"]))
		"unlock_ability":
			if not state.abilities_unlocked.has(e["ability"]):
				state.abilities_unlocked.append(str(e["ability"]))
		"equip":
			state.equipped[str(e["category"])] = str(e["item"])
		"toast":
			messages.append(str(e["text"]))
		_:
			push_error("Unknown effect type: %s" % e.get("type", ""))
