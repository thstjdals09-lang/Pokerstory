extends Node
## Global game session (autoload "Game"): content data, the current GameState,
## saving, and the rule actions the UI calls. UI never edits GameState directly.

signal state_changed
signal toast_requested(text: String)
## The current odd-job run started, progressed, finished or was cancelled.
signal job_changed

const DEFAULT_SAVE_PATH := "user://save_slot_1.json"
const DEFAULT_PLAYER_NAME := "여행자"

const INPUT_BINDINGS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"interact": [KEY_E, KEY_ENTER, KEY_KP_ENTER],
	"menu": [KEY_ESCAPE],
	"toggle_goal": [KEY_TAB],
	"card_1": [KEY_1],
	"card_2": [KEY_2],
	"card_3": [KEY_3],
	"card_4": [KEY_4],
	"card_5": [KEY_5],
}

var data := DataDB.new()
var data_errors: Array = []
var state: GameState = null
var save_path := DEFAULT_SAVE_PATH
## Test hook: card-code lists used (in order) as stacked decks before falling back to random decks.
var debug_deck_queue: Array = []
## Seed of the most recent random deck, printed so a hand can be reproduced.
var last_deck_seed := 0
## The odd job in progress (not saved), or null.
var job: PlazaJob = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_setup_input_map()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-path="):
			save_path = arg.get_slice("=", 1)
	data_errors = data.load_all("res://data")
	for e in data_errors:
		push_error("Data error: " + str(e))
	_rng.randomize()


func _setup_input_map() -> void:
	for action in INPUT_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in INPUT_BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


# --- session -----------------------------------------------------------------

func new_game(player_name: String) -> void:
	state = GameState.new()
	var clean := player_name.strip_edges()
	state.player_name = clean if clean != "" else DEFAULT_PLAYER_NAME
	state.add_chips(int(poker_economy().get("starting_chips", 0)), "starting_chips")
	state.current_scene = "village_square"
	save_game()
	state_changed.emit()


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func load_game() -> Dictionary:
	var result := SaveSystem.load_state(save_path)
	if result["ok"]:
		state = result["state"]
		job = null
		# A hand interrupted by a crash or forced kill: its stake comes back once.
		var refunded := PokerEconomy.void_pending(state)
		result["refunded_stake"] = refunded
		if refunded > 0:
			save_game()
		state_changed.emit()
	return result


func save_game() -> bool:
	if state == null:
		return false
	var err := SaveSystem.save(state, save_path)
	if err != OK:
		push_error("Save failed: %s" % error_string(err))
		toast_requested.emit("저장에 실패했어요.")
		return false
	return true


func end_session() -> void:
	state = null
	job = null


func set_location(location_id: String) -> void:
	state.current_scene = location_id
	save_game()


# --- flags and text ----------------------------------------------------------

## Sets the given flags; saves only if something changed.
func apply_flags(flag_names: Array) -> void:
	var changed := false
	for f in flag_names:
		if not state.get_flag(f):
			state.set_flag(f)
			changed = true
	if changed:
		save_game()
		state_changed.emit()


## Placeholder values for dialogue and goal text.
func text_vars() -> Dictionary:
	var vars := {
		"player": state.player_name if state else DEFAULT_PLAYER_NAME,
		"max_discards": int(poker_rules().get("max_discards", 3)),
	}
	var econ := poker_economy()
	for k in econ:
		if not str(k).begins_with("_"):
			vars[k] = int(econ[k])
	for id in data.items:
		vars["price_" + id] = data.item_price(id)
	for id in data.quests:
		vars["reward_" + id] = int(data.quests[id].get("reward", 0))
	for id in data.jobs:
		vars["reward_" + id] = int(data.jobs[id].get("reward", 0))
	return vars


func current_goal() -> String:
	if state == null:
		return ""
	if job != null:
		return "아르바이트 · 광장의 카드와 칩 줍기 (%d / %d)" % [job.collected.size(), job.total()]
	for g in data.goals:
		if Conditions.check(g.get("conditions", {}), state, state.current_scene):
			return DialogueResolver.format_line(g["text"], text_vars())
	return ""


# --- poker -------------------------------------------------------------------

func poker_rules() -> Dictionary:
	return data.poker.get("rules", {})


func poker_economy() -> Dictionary:
	return data.poker.get("economy", {})


func player_ability() -> Dictionary:
	return data.abilities.get(data.poker.get("player_ability", ""), {})


func poker_stake() -> int:
	return PokerEconomy.stake(poker_economy())


func can_join_poker() -> bool:
	return state != null and PokerEconomy.can_join(state, poker_economy())


## Starts a hand and takes the stake (saved at once). Returns null if the player cannot join.
func create_poker_match() -> PokerMatch:
	if not PokerEconomy.place_stake(state, poker_economy()):
		return null
	save_game()
	state_changed.emit()
	var deck: Deck
	if not debug_deck_queue.is_empty():
		deck = Deck.stacked(debug_deck_queue.pop_front())
	else:
		last_deck_seed = _rng.randi()
		deck = Deck.shuffled(last_deck_seed)
		print("[poker] deck seed %d" % last_deck_seed)
	return PokerMatch.new(deck, int(poker_rules().get("max_discards", 3)), int(poker_rules().get("hand_size", 5)))


## Pays out a finished hand once, then saves.
func settle_match(m: PokerMatch) -> Dictionary:
	var result := PokerEconomy.settle(state, m, poker_economy())
	if result["ok"]:
		save_game()
		state_changed.emit()
	return result


## Leaving the table before the showdown: the hand is folded and the stake is not returned.
func fold_match(m: PokerMatch) -> Dictionary:
	var result := PokerEconomy.fold(state, m)
	if result["ok"]:
		save_game()
		state_changed.emit()
	return result


# --- time of day -------------------------------------------------------------

func set_time(time: String) -> void:
	if time != "day" and time != "evening":
		return
	state.time_of_day = time
	save_game()
	state_changed.emit()


# --- quests ------------------------------------------------------------------

func accept_quest(quest_id: String) -> bool:
	if not data.quests.has(quest_id) or not QuestBook.accept(state, quest_id):
		return false
	save_game()
	state_changed.emit()
	return true


func complete_quest(quest_id: String) -> Dictionary:
	if not data.quests.has(quest_id):
		return {"ok": false}
	var result := QuestBook.complete(state, data.quests[quest_id])
	if result["ok"]:
		save_game()
		state_changed.emit()
	return result


# --- odd jobs ----------------------------------------------------------------

func start_job(job_id: String) -> bool:
	if job != null or not data.jobs.has(job_id):
		return false
	job = PlazaJob.create(data.jobs[job_id], _rng)
	job_changed.emit()
	state_changed.emit()
	return true


## Collects one spot. Pays the reward only when the last spot is collected.
## Returns {"ok": bool, "collected": n, "total": n, "done": bool, "reward": n}.
func collect_job_spot(spot_id: String) -> Dictionary:
	if job == null:
		return {"ok": false}
	var result := job.collect(state, spot_id)
	if not result["ok"]:
		return result
	if result["done"]:
		job = null
		save_game()
	job_changed.emit()
	state_changed.emit()
	return result


func cancel_job() -> bool:
	if job == null:
		return false
	job = null
	job_changed.emit()
	state_changed.emit()
	return true


# --- shop and home -----------------------------------------------------------

func buy_item(item_id: String) -> Dictionary:
	if not data.items.has(item_id):
		return {"ok": false, "reason": "unknown_item"}
	var price := data.item_price(item_id)
	if state.chips_balance < price:
		return {"ok": false, "reason": "not_enough_chips", "need": price - state.chips_balance}
	if not state.purchase(item_id, price):
		return {"ok": false, "reason": "failed"}
	save_game()
	state_changed.emit()
	return {"ok": true}


func home_slots() -> Array:
	return data.locations.get("player_home", {}).get("slots", [])


func slot_name(slot_id: String) -> String:
	for s in home_slots():
		if s["id"] == slot_id:
			return s["name"]
	return slot_id


func place_item(slot_id: String, item_id: String) -> bool:
	var known_slot := false
	for s in home_slots():
		known_slot = known_slot or s["id"] == slot_id
	if not known_slot or not data.items.get(item_id, {}).get("placeable", false):
		return false
	if not state.place_item(slot_id, item_id):
		return false
	save_game()
	state_changed.emit()
	return true


func remove_placement(slot_id: String) -> bool:
	if not state.remove_placement(slot_id):
		return false
	save_game()
	state_changed.emit()
	return true
