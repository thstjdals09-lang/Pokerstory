class_name QuestBook
extends RefCounted
## One-time resident requests (data/quests.json). State lives in GameState.quests.
## A quest pays its reward only on the transition active -> completed, so it pays once.

const NOT_STARTED := "not_started"
const ACTIVE := "active"
const COMPLETED := "completed"


static func state_of(state: GameState, quest_id: String) -> String:
	return str(state.quests.get(quest_id, NOT_STARTED))


static func accept(state: GameState, quest_id: String) -> bool:
	if state_of(state, quest_id) != NOT_STARTED:
		return false
	state.quests[quest_id] = ACTIVE
	return true


## Returns {"ok": true, "reward": n} or {"ok": false} when the quest is not active.
static func complete(state: GameState, quest: Dictionary) -> Dictionary:
	var quest_id: String = quest["id"]
	if state_of(state, quest_id) != ACTIVE:
		return {"ok": false}
	state.quests[quest_id] = COMPLETED
	var reward := int(quest.get("reward", 0))
	state.add_chips(reward, "quest:" + quest_id)
	return {"ok": true, "reward": reward}
