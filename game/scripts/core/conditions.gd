class_name Conditions
extends RefCounted
## Evaluates data-defined conditions (dialogue entries and choices, goals, places, objects, quests,
## projects) against the game state. Every key present must hold; an empty dictionary always matches.
## Composition: "all": [cond, ...], "any": [cond, ...], "not": cond.

const KNOWN_KEYS := [
	"all", "any", "not",
	"flags_true", "flags_false",
	"placed_item", "not_placed_item",
	"owns_or_placed_item", "not_owned_or_placed",
	"min_poker_hands", "max_poker_hands",
	"min_chips", "max_chips",
	"quest_not_started", "quest_active", "quest_completed",
	"quests_completed_min", "episodes_completed_min",
	"time", "location",
	"met", "not_met", "residents_met_min",
	"friendship_min", "rivalry_min", "poker_vs_min",
	"romance_stage", "romance_consent",
	"edge_phase",
	"project_complete", "project_not_complete", "projects_complete_min",
	"home_stage_min", "home_stage_max",
	"event_done", "event_not_done",
	"contributions_min", "contributed",
	"jobs_completed_min",
	"item_discovered",
]
const ITEM_KEYS := ["placed_item", "not_placed_item", "owns_or_placed_item", "not_owned_or_placed", "item_discovered"]
const QUEST_KEYS := ["quest_not_started", "quest_active", "quest_completed"]
const NPC_KEYS := ["met", "not_met"]
const NPC_MAP_KEYS := ["friendship_min", "rivalry_min", "poker_vs_min", "romance_stage", "romance_consent"]
const PROJECT_KEYS := ["project_complete", "project_not_complete"]


static func check(cond: Dictionary, state: GameState, location: String = "") -> bool:
	for key in cond:
		if not _check_key(key, cond[key], state, location):
			return false
	return true


static func _check_key(key: String, v, state: GameState, location: String) -> bool:
	match key:
		"all":
			for c in v:
				if not check(c, state, location):
					return false
			return true
		"any":
			for c in v:
				if check(c, state, location):
					return true
			return false
		"not":
			return not check(v, state, location)
		"flags_true":
			for f in v:
				if not state.get_flag(f):
					return false
			return true
		"flags_false":
			for f in v:
				if state.get_flag(f):
					return false
			return true
		"placed_item":
			return state.is_item_placed(v)
		"not_placed_item":
			return not state.is_item_placed(v)
		"owns_or_placed_item":
			return state.owned_count(v) > 0 or state.is_item_placed(v)
		"not_owned_or_placed":
			return state.owned_count(v) <= 0 and not state.is_item_placed(v)
		"item_discovered":
			return state.collection.has(v)
		"min_poker_hands":
			return state.poker_hands_completed >= int(v)
		"max_poker_hands":
			return state.poker_hands_completed <= int(v)
		"min_chips":
			return state.chips_balance >= int(v)
		"max_chips":
			return state.chips_balance <= int(v)
		"quest_not_started":
			return QuestBook.state_of(state, v) == QuestBook.NOT_STARTED
		"quest_active":
			return QuestBook.state_of(state, v) == QuestBook.ACTIVE
		"quest_completed":
			return QuestBook.state_of(state, v) == QuestBook.COMPLETED
		"quests_completed_min":
			var n := 0
			for q in state.quests:
				n += 1 if state.quests[q] == QuestBook.COMPLETED and not str(q).contains(".bond_") else 0
			return n >= int(v)
		"episodes_completed_min":
			var e := 0
			for q in state.quests:
				e += 1 if state.quests[q] == QuestBook.COMPLETED and str(q).contains(".bond_") else 0
			return e >= int(v)
		"time":
			return state.time_of_day == v
		"location":
			return location == v
		"met":
			return state.has_met(v)
		"not_met":
			return not state.has_met(v)
		"residents_met_min":
			return state.residents_met() >= int(v)
		"friendship_min":
			for npc in v:
				if state.relation(npc)["friendship"] < int(v[npc]):
					return false
			return true
		"rivalry_min":
			for npc in v:
				if state.relation(npc)["rivalry"] < int(v[npc]):
					return false
			return true
		"poker_vs_min":
			for npc in v:
				if int(state.relation(npc)["poker_hands"]) < int(v[npc]):
					return false
			return true
		"romance_stage":
			for npc in v:
				var want = v[npc]
				var stage: String = state.relation(npc)["romance"]["stage"]
				if want is Array:
					if not want.has(stage):
						return false
				elif stage != want:
					return false
			return true
		"romance_consent":
			for npc in v:
				if bool(state.relation(npc)["romance"]["consent"]) != bool(v[npc]):
					return false
			return true
		"edge_phase":
			for pair in v:
				var want = v[pair]
				var phase := state.edge_phase(pair)
				if want is Array:
					if not want.has(phase):
						return false
				elif phase != want:
					return false
			return true
		"project_complete":
			return state.project_done(v)
		"project_not_complete":
			return not state.project_done(v)
		"projects_complete_min":
			return state.projects.size() >= int(v)
		"home_stage_min":
			return state.home_stage >= int(v)
		"home_stage_max":
			return state.home_stage <= int(v)
		"event_done":
			return state.events_done.has(v)
		"event_not_done":
			return not state.events_done.has(v)
		"contributions_min":
			return state.contributions.size() >= int(v)
		"contributed":
			return state.contributions.has(str(v))
		"jobs_completed_min":
			return state.jobs_completed >= int(v)
	push_error("Unknown condition key: %s" % key)
	return false
