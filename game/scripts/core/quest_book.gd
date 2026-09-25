class_name QuestBook
extends RefCounted
## One-time tasks: resident requests (data/quests.json, kind "quest") and personal resident
## episodes (data/episodes.json, kind "episode"). State lives in GameState.quests.
## Rewards and effects are applied only on the transition active -> completed, so each task pays once.

const NOT_STARTED := "not_started"
const ACTIVE := "active"
const COMPLETED := "completed"
const EPISODE_FRIENDSHIP := 8
const REQUEST_FRIENDSHIP := 4


static func state_of(state: GameState, quest_id: String) -> String:
	return str(state.quests.get(quest_id, NOT_STARTED))


static func accept(state: GameState, quest_id: String) -> bool:
	if state_of(state, quest_id) != NOT_STARTED:
		return false
	state.quests[quest_id] = ACTIVE
	return true


## Completes an active task. `option` picks one of the task's handoff options (episodes).
## Returns {"ok": true, "reward": n, "messages": [...], "option": {...}} or {"ok": false}.
static func complete(state: GameState, quest: Dictionary, option: int = -1) -> Dictionary:
	var quest_id: String = quest["id"]
	if state_of(state, quest_id) != ACTIVE:
		return {"ok": false}
	state.quests[quest_id] = COMPLETED
	var reward := int(quest.get("reward", 0))
	state.add_chips(reward, "quest:" + quest_id)
	var effects: Array = []
	effects.append_array(quest.get("effects", []))
	if quest.get("kind", "quest") == "episode":
		effects.append({"type": "friendship", "npc": quest["giver"], "amount": EPISODE_FRIENDSHIP})
		effects.append({"type": "memory", "npc": quest["giver"], "id": quest_id})
	else:
		# Resident requests count toward the festival (act 3) once each, and both residents
		# remember who helped (content alpha).
		effects.append({"type": "contribution", "id": "quest:" + quest_id})
		effects.append({"type": "memory", "npc": quest["giver"], "id": quest_id})
		effects.append({"type": "friendship", "npc": quest["giver"], "amount": REQUEST_FRIENDSHIP})
		if str(quest.get("target", "")).begins_with("npc_"):
			effects.append({"type": "memory", "npc": quest["target"], "id": quest_id})
			effects.append({"type": "friendship", "npc": quest["target"], "amount": 2})
	var chosen: Dictionary = {}
	var options: Array = quest.get("options", [])
	if option >= 0 and option < options.size():
		chosen = options[option]
		effects.append_array(chosen.get("effects", []))
		# The choice is remembered, so the giver can answer it later (content finishing).
		effects.append({"type": "flag", "flag": "choice:%s:%d" % [quest_id, option]})
	effects.append({"type": "flag", "flag": "done:" + quest_id})
	var applied := Effects.apply(state, effects)
	return {"ok": true, "reward": reward, "messages": applied.get("messages", []), "option": chosen}
