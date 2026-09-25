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
## Test hook: the next N saves fail (save-failure rollback tests).
var debug_fail_saves := 0
## True when the last persistent change was rolled back because its save failed.
var last_commit_failed := false
## Seed of the most recent random deck, printed so a hand can be reproduced.
var last_deck_seed := 0
## The odd job in progress (not saved), or null.
var job: PlazaJob = null
## An unfinished hand restored by load_game, waiting for Main to reopen the table.
var resumed_match: PokerMatch = null
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
		resumed_match = null
		# An interrupted hand continues exactly where it stopped (Design Review 03, D2).
		if not state.poker_in_progress.is_empty():
			resumed_match = PokerMatch.from_dict(state.poker_in_progress)
		elif result["legacy_stake"]:
			# One-time exception for saves from before v3 (Design Review 04, R2): the stake was paid but
			# the cards were never saved. The paid stake carries over to a newly dealt hand, and the
			# save is rewritten as v3 with that hand at once, so loading the same save again resumes
			# this hand instead of dealing another. Nothing is refunded or charged again.
			resumed_match = _deal_match()
			state.poker_in_progress = resumed_match.to_dict()
			save_game()
			result["legacy_hand"] = true
		result["resumed_hand"] = resumed_match != null
		state_changed.emit()
	return result


func save_game() -> bool:
	if state == null:
		return false
	if debug_fail_saves > 0:
		# Test hook: the next N saves fail as if the disk refused the write.
		debug_fail_saves -= 1
		push_warning("Save failed (injected for a test)")
		toast_requested.emit("저장에 실패했어요.")
		return false
	var err := SaveSystem.save(state, save_path)
	if err != OK:
		push_error("Save failed: %s" % error_string(err))
		toast_requested.emit("저장에 실패했어요.")
		return false
	return true


## Runs one persistent change together with its save (StateTransaction). On a failed save the state
## is back to how it was, `undo_session` restores session objects changed along with it (job
## progress, the poker hand object), and the player is told to try again.
func _commit(change: Callable, undo_session: Callable = Callable()) -> Dictionary:
	var r := StateTransaction.run(state, change, save_game)
	last_commit_failed = r.get("reason", "") == "save_failed"
	if last_commit_failed:
		if undo_session.is_valid():
			undo_session.call()
		toast_requested.emit("저장하지 못해서 방금 한 일을 되돌렸어요. 다시 시도해 주세요.")
		state_changed.emit()
	elif r.get("ok", false) and not r.get("skipped", false):
		state_changed.emit()
	return r


func end_session() -> void:
	state = null
	job = null
	resumed_match = null


## Hands the restored unfinished hand to the caller once.
func take_resumed_match() -> PokerMatch:
	var m := resumed_match
	resumed_match = null
	return m


func set_location(location_id: String) -> void:
	state.current_scene = location_id
	save_game()


# --- flags and text ----------------------------------------------------------

## Sets the given flags; saves only if something changed.
func apply_flags(flag_names: Array) -> void:
	var change := func() -> Dictionary:
		var changed := false
		for f in flag_names:
			if not state.get_flag(f):
				state.set_flag(f)
				changed = true
		return {"ok": true, "skipped": not changed}
	_commit(change)


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
		vars["count_" + id] = int(data.jobs[id].get("count", 0))
	return vars


## HUD lines for quests in progress (Design Review 03, D6): the parcel is tracked as quest state,
## not as an inventory item, so the HUD is where the player sees it.
func active_quest_lines() -> Array:
	var lines: Array = []
	if state == null:
		return lines
	var active: Array = []
	for id in data.quest_order:
		if QuestBook.state_of(state, id) == QuestBook.ACTIVE:
			active.append(id)
	if active.is_empty():
		return lines
	# One tracked task with where its target is right now (06_integration/07); the rest is in the journal.
	var shown: String = state.tracked_quest if active.has(state.tracked_quest) else active[0]
	var q: Dictionary = data.quests[shown]
	var carry := " (%s 소지)" % q["item_name"] if q.has("item_name") else ""
	var label := "의뢰 중" if data.is_quest(shown) else "이야기"
	lines.append("%s · %s%s → %s" % [label, q["name"], carry, npc_where_text(str(q["target"]))])
	if active.size() > 1:
		lines.append("진행 중인 일 %d개 · 메뉴 > 일지에서 확인" % active.size())
	return lines


func current_goal() -> String:
	if state == null:
		return ""
	if job != null:
		var jdef: Dictionary = data.jobs[job.job_id]
		if job.job_type == "deliver":
			return "아르바이트 · %s에게 편지 전하기 (%s)" % [data.npc_name(job.recipient), npc_where_text(job.recipient)]
		return "아르바이트 · %s (%d / %d)" % [jdef.get("name", ""), job.done_count(), job.total()]
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


## Poker tables (content v0.3, 05_poker/01): one rule engine, several tables.
func poker_mode(mode: String) -> Dictionary:
	return data.poker.get("modes", {}).get(mode, {})


func poker_stake(mode: String = "homegame") -> int:
	return 0 if mode == "practice" else PokerEconomy.stake(poker_economy())


func can_join_poker(mode: String = "homegame") -> bool:
	return state != null and state.poker_in_progress.is_empty() \
		and PokerEconomy.can_join(state, poker_economy(), poker_stake(mode))


## The card-room regular (the first-play opponent) and the practice partner.
func default_opponent(mode: String = "homegame") -> String:
	return "npc_moa" if mode == "practice" else str(poker_rules().get("opponent", "npc_lumi"))


func match_opponent(m: PokerMatch) -> String:
	return m.opponent_id if m.opponent_id != "" else default_opponent(m.mode)


## Residents who will sit down for `mode` right now: the mode's list (or every opponent for a home
## game), only residents already met.
func poker_opponents(mode: String) -> Array:
	var pool: Array = poker_mode(mode).get("opponents", data.opponents.keys())
	return pool.filter(func(npc): return data.opponents.has(npc) and state.has_met(npc))


func tournament_opponent() -> String:
	var stages: Array = poker_mode("tournament").get("stages", [])
	return str(stages[clampi(int(state.tournament.get("stage", 0)), 0, stages.size() - 1)]) if not stages.is_empty() else ""


## The ability a hand uses: the one picked for it, else the first ability (Star Sense).
func match_ability(m: PokerMatch) -> Dictionary:
	var id := data.ability_aliases.get(m.ability_id, m.ability_id) as String
	return data.abilities.get(id, player_ability())


## Starts a hand and takes the stake (saved at once). Returns null if the player cannot join.
## Practice hands take no stake and pay nothing, but are saved and resumed the same way.
func create_poker_match(mode: String = "homegame", opponent: String = "", ability_id: String = "") -> PokerMatch:
	if not can_join_poker(mode):
		return null
	if mode == "tournament":
		opponent = tournament_opponent()
	if opponent == "":
		opponent = default_opponent(mode)
	var stake := poker_stake(mode)
	var box := {}
	# The stake and the dealt cards are saved together, so a restart resumes this exact hand;
	# if that save fails there is no hand and no stake.
	var change := func() -> Dictionary:
		if stake > 0 and not PokerEconomy.place_stake(state, poker_economy()):
			return {"ok": false}
		var m := _deal_match()
		m.mode = mode
		m.opponent_id = opponent
		m.persona = str(data.opponents.get(opponent, {}).get("persona", "steady"))
		var aid := str(data.ability_aliases.get(ability_id, ability_id))
		m.ability_id = aid if state.abilities_unlocked.has(aid) else str(poker_rules().get("player_ability", data.poker.get("player_ability", "")))
		m.stake = stake
		m.place = state.current_scene
		state.poker_in_progress = m.to_dict()
		box["m"] = m
		return {"ok": true}
	var r := _commit(change)
	return box["m"] if r["ok"] else null


func _deal_match() -> PokerMatch:
	var deck: Deck
	if not debug_deck_queue.is_empty():
		deck = Deck.stacked(debug_deck_queue.pop_front())
	else:
		last_deck_seed = _rng.randi()
		deck = Deck.shuffled(last_deck_seed)
		print("[poker] deck seed %d" % last_deck_seed)
	return PokerMatch.new(deck, int(poker_rules().get("max_discards", 3)), int(poker_rules().get("hand_size", 5)))


## Uses an ability on the current hand and saves the hand, so the use survives a restart.
## Only public table history about this opponent is passed in.
func use_poker_ability(m: PokerMatch, ability: Dictionary, context: Dictionary = {}) -> Dictionary:
	var ctx := context.duplicate()
	ctx["history"] = state.poker_history.get(match_opponent(m), [])
	var before := m.to_dict()
	var change := func() -> Dictionary:
		var result := m.use_ability(ability, ctx)
		if result["ok"]:
			state.poker_in_progress = m.to_dict()
		return result
	return _commit(change, func(): m.restore_progress(before))


## Pays out a finished hand once, then saves. Practice hands settle without chips.
func settle_match(m: PokerMatch) -> Dictionary:
	var key := PokerEconomy.outcome_key(m.outcome)
	# If the settlement cannot be saved nothing is paid and the hand stays unsettled; the table
	# offers to save again (the same showdown, never a new deal).
	var change := func() -> Dictionary:
		if m.mode == "practice":
			if m.settled or m.phase != PokerMatch.Phase.SHOWDOWN:
				return {"ok": false}
			m.settled = true
			state.poker_in_progress = {}
			return {"ok": true, "outcome": key, "stake": 0, "payout": 0, "net": 0, "practice": true, "balance": state.chips_balance}
		var result := PokerEconomy.settle(state, m, poker_economy())
		if result["ok"]:
			_after_hand(m, result)
			state.poker_in_progress = {}
		return result
	return _commit(change, func(): m.settled = false)


## What a finished (paid) hand leaves behind: public table history, the hand count with this
## resident, rivalry (never friendship), a festival contribution in act 3, tournament progress.
func _after_hand(m: PokerMatch, result: Dictionary) -> void:
	var opp := match_opponent(m)
	result["opponent"] = opp
	var hist: Array = state.poker_history.get(opp, [])
	hist.append({"discards": m.opponent_discards.size(), "hand": str(m.opponent_eval.get("name", "")), "outcome": result["outcome"]})
	state.poker_history[opp] = hist.slice(maxi(0, hist.size() - 10))
	var rel := state.relation(opp)
	rel["poker_hands"] = int(rel["poker_hands"]) + 1
	# Social memory (content alpha): the first hand together, the first win against them (a small
	# one-time prize, never a consolation for losing), the tournament meeting, the mode's context.
	var firsts: Array = [{"type": "memory", "npc": opp, "id": "poker_first"}]
	if m.mode == "tournament":
		firsts.append({"type": "memory", "npc": opp, "id": "poker_tournament"})
	elif m.mode == "friendly_challenge":
		firsts.append({"type": "memory", "npc": opp, "id": "poker_challenge"})
	elif m.mode == "homegame" and m.place.begins_with("player_home"):
		firsts.append({"type": "memory", "npc": opp, "id": "poker_house"})
	if result["outcome"] == "win":
		# Not during the first-play prologue: its approved economy (win +20 net, no bonuses) stays exact.
		var bonus := int(poker_economy().get("first_win_bonus", 0)) if state.get_flag("story.act1_started") else 0
		if bonus > 0:
			firsts.append({"type": "chips", "amount": bonus, "reason": "poker_first_win:" + opp, "once": "poker_first_win:" + opp})
			if not state.events_done.has("poker_first_win:" + opp):
				result["first_win_bonus"] = bonus
		firsts.append({"type": "memory", "npc": opp, "id": "poker_beat"})
	Effects.apply(state, firsts)
	Effects.apply(state, [
		{"type": "rivalry", "npc": opp, "amount": RIVALRY_PER_HAND},
		{"type": "contribution", "id": "poker:first"},
	])
	if m.mode == "social_mix" and m.place == "tea_house":
		state.set_flag("tea.social_played")
	if m.mode == "tournament":
		var stage := int(state.tournament.get("stage", 0))
		var seen: Array = poker_mode("tournament").get("stage_flags", [])
		if stage < seen.size():
			state.set_flag(str(seen[stage]))
		if result["outcome"] == "win":
			var prizes: Array = poker_mode("tournament").get("round_prizes", [])
			if stage < prizes.size() and int(prizes[stage]) > 0:
				var key := "tournament_prize:%d" % stage
				if not state.events_done.has(key):
					result["round_prize"] = int(prizes[stage])
				Effects.apply(state, [{"type": "chips", "amount": int(prizes[stage]), "reason": key, "once": key}])
			stage += 1
			if stage >= poker_mode("tournament").get("stages", []).size():
				stage = 0
				result["tournament_won"] = true
				if not bool(state.tournament.get("rewarded", false)):
					state.tournament["rewarded"] = true
					state.grant_item(str(poker_mode("tournament")["reward_item"]))
					state.set_flag("festival.tournament_won")
					result["reward_item"] = str(poker_mode("tournament")["reward_item"])
		state.tournament["stage"] = stage
		result["tournament_stage"] = stage


## Leaving the table before the showdown: the hand is folded and the stake is not returned.
## A practice hand simply ends.
func fold_match(m: PokerMatch) -> Dictionary:
	var change := func() -> Dictionary:
		var result: Dictionary
		if m.mode == "practice":
			if m.settled or m.phase != PokerMatch.Phase.DRAW:
				return {"ok": false}
			m.settled = true
			result = {"ok": true, "stake": 0}
		else:
			result = PokerEconomy.fold(state, m)
		if result["ok"]:
			state.poker_in_progress = {}
		return result
	return _commit(change, func(): m.settled = false)


func opponent_line(npc: String, key: String) -> String:
	var lines: Dictionary = data.opponents.get(npc, {}).get("lines", data.poker.get("opponent_lines", {}))
	return str(lines.get(key, ""))


# --- time of day -------------------------------------------------------------

func set_time(time: String) -> bool:
	if time != "day" and time != "evening":
		return false
	var change := func() -> Dictionary:
		if state.time_of_day == "evening" and time == "day":
			state.day_count += 1
		state.time_of_day = time
		return {"ok": true}
	return _commit(change)["ok"]


# --- quests ------------------------------------------------------------------

func quest_available(quest_id: String) -> bool:
	var q: Dictionary = data.quests.get(quest_id, {})
	return not q.is_empty() and QuestBook.state_of(state, quest_id) == QuestBook.NOT_STARTED \
		and Conditions.check(q.get("unlock", {}), state)


func accept_quest(quest_id: String) -> bool:
	if not data.quests.has(quest_id) or not Conditions.check(data.quests[quest_id].get("unlock", {}), state):
		return false
	var change := func() -> Dictionary:
		if not QuestBook.accept(state, quest_id):
			return {"ok": false}
		if state.tracked_quest == "" or QuestBook.state_of(state, state.tracked_quest) != QuestBook.ACTIVE:
			state.tracked_quest = quest_id
		return {"ok": true}
	return _commit(change)["ok"]


## Completes an active task (arg "id" or "id|option").
func complete_quest(arg: String) -> Dictionary:
	var quest_id := arg.get_slice("|", 0)
	var option := int(arg.get_slice("|", 1)) if arg.contains("|") else -1
	if not data.quests.has(quest_id):
		return {"ok": false}
	var change := func() -> Dictionary:
		var r := QuestBook.complete(state, data.quests[quest_id], option)
		if r["ok"] and state.tracked_quest == quest_id:
			state.tracked_quest = _first_active_quest()
		return r
	var result := _commit(change)
	if result["ok"]:
		for m in result.get("messages", []):
			toast_requested.emit(m)
	return result


func _first_active_quest() -> String:
	for id in data.quest_order:
		if QuestBook.state_of(state, id) == QuestBook.ACTIVE:
			return id
	return ""


# --- odd jobs ----------------------------------------------------------------

func start_job(job_id: String) -> bool:
	if job != null or not data.jobs.has(job_id):
		return false
	job = PlazaJob.create(data.jobs[job_id], _rng, state.jobs_completed + 1)
	job_changed.emit()
	state_changed.emit()
	return true


## deliver / shelve steps; same payout rules as collect_job_spot.
func job_step(kind: String, value: String) -> Dictionary:
	if job == null:
		return {"ok": false}
	var run: PlazaJob = job
	return _job_step(func() -> Dictionary: return run.deliver(state, value) if kind == "deliver" else run.shelve(state, value))


## Collects one spot. Pays the reward only when the last spot is collected.
## Returns {"ok": bool, "collected": n, "total": n, "done": bool, "reward": n}.
func collect_job_spot(spot_id: String) -> Dictionary:
	if job == null:
		return {"ok": false}
	var run: PlazaJob = job
	return _job_step(func() -> Dictionary: return run.collect(state, spot_id))


## One job step. Steps before the last change only the session's job; the last step pays and is
## saved as one unit with the payment (on a failed save the last step is undone, unpaid).
func _job_step(step: Callable) -> Dictionary:
	var run: PlazaJob = job
	var collected_before := run.collected.duplicate()
	var change := func() -> Dictionary:
		var r: Dictionary = step.call()
		if r["ok"] and not r["done"]:
			r["skipped"] = true
		elif r["ok"]:
			state.set_flag("job_done:" + run.job_id)
			r["line"] = job_done_line(run.job_id)
		return r
	var undo := func():
		run.collected = collected_before
		run.rewarded = false
	var result := _commit(change, undo)
	if result["ok"] and result.get("done", false):
		job = null
	if result["ok"] or result.get("reason", "") == "save_failed":
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
	if not item_on_sale(item_id):
		return {"ok": false, "reason": "not_on_sale"}
	var price := data.item_price(item_id)
	if state.chips_balance < price:
		return {"ok": false, "reason": "not_enough_chips", "need": price - state.chips_balance}
	var change := func() -> Dictionary: return {"ok": state.purchase(item_id, price), "reason": "failed"}
	return _commit(change)


const RIVALRY_PER_HAND := 5
const HOME_LOCATIONS := ["player_home", "player_home_annex", "player_home_hall"]


## Furniture slots usable right now in a home room (slots appear with the house stages).
func home_slots(loc_id: String = "player_home") -> Array:
	return data.locations.get(loc_id, {}).get("slots", []).filter(
		func(s): return Conditions.check(s.get("conditions", {}), state, loc_id))


func slot_name(slot_id: String) -> String:
	for loc_id in HOME_LOCATIONS:
		for s in data.locations.get(loc_id, {}).get("slots", []):
			if s["id"] == slot_id:
				return s["name"] if s.has("name") else slot_id
	return slot_id


## Items that can go into slots: furniture, decor and mementos (clothing and styles are equipped).
func is_placeable(item_id: String) -> bool:
	var item: Dictionary = data.items.get(item_id, {})
	return item.get("placeable", false) and DataDB.PLACEABLE_CATEGORIES.has(str(item.get("category", "furniture")))


func place_item(slot_id: String, item_id: String) -> bool:
	var known_slot := false
	for loc_id in HOME_LOCATIONS:
		for s in home_slots(loc_id):
			known_slot = known_slot or s["id"] == slot_id
	if not known_slot or not is_placeable(item_id):
		return false
	var change := func() -> Dictionary: return {"ok": state.place_item(slot_id, item_id)}
	return _commit(change)["ok"]


func remove_placement(slot_id: String) -> bool:
	var change := func() -> Dictionary: return {"ok": state.remove_placement(slot_id)}
	return _commit(change)["ok"]


# --- content v0.3: effects, residents, dialogue ----------------------------------

## Runs data effects (at most once per non-empty key) and saves. Returns Effects.apply's result.
func run_effects(effects: Array, key: String = "") -> Dictionary:
	var change := func() -> Dictionary: return Effects.apply(state, effects, key)
	var r := _commit(change)
	if r["ok"] and not r.get("skipped", false):
		for m in r["messages"]:
			toast_requested.emit(m)
	return r


func npc_place(npc_id: String) -> Dictionary:
	return data.npc_place(npc_id, state.time_of_day, state)


func location_name(loc_id: String) -> String:
	return str(data.locations.get(loc_id, {}).get("name", loc_id))


## "루미: 지금 마을 광장 (저녁엔 카드룸)" for HUD, journal and hints.
func npc_where_text(target: String) -> String:
	if not data.npcs.has(target):
		# A place or object in the village: name it and where it is.
		for loc_id in data.locations:
			for it in data.locations[loc_id].get("interactables", []):
				if it["id"] == target:
					return "%s: %s" % [str(it.get("title", it.get("prompt", target))), location_name(loc_id)]
		return "대상 위치 확인"
	var here := npc_place(target)
	var other_time := "evening" if state.time_of_day == "day" else "day"
	var other := data.npc_place(target, other_time, state)
	var text := "%s: 지금 %s" % [data.npc_name(target), location_name(here["loc"])] if here.has("loc") \
		else "%s: 지금은 만날 수 없어요" % data.npc_name(target)
	if other.has("loc") and other.get("loc", "") != here.get("loc", ""):
		text += " (%s엔 %s)" % ["저녁" if other_time == "evening" else "낮", location_name(other["loc"])]
	return text


func speaker_name(speaker: String) -> String:
	if speaker.begins_with("obj:"):
		var id := speaker.substr(4)
		for loc_id in data.locations:
			for it in data.locations[loc_id].get("interactables", []):
				if it["id"] == id:
					return str(it.get("title", ""))
		return ""
	return data.npc_name(speaker)


func resolve_entry(speaker: String, location: String) -> Dictionary:
	return DialogueResolver.resolve(data.dialogue, speaker, location, state)


## Choices shown for `entry`: its own (condition-filtered) plus what the world adds:
## handing over tasks to this resident, the current letter job, offers of this resident's tasks,
## and a poker invitation where residents play. The hand-over comes first (D4, 03_residents/04).
func entry_choices(entry: Dictionary, speaker: String, location: String) -> Array:
	var base: Array = []
	for c in entry.get("choices", []):
		if Conditions.check(c.get("conditions", {}), state, location):
			base.append(c)
	var out: Array = []
	var target := speaker.substr(4) if speaker.begins_with("obj:") else speaker
	for id in data.quest_order:
		var q: Dictionary = data.quests[id]
		if str(q.get("target", "")) != target or QuestBook.state_of(state, id) != QuestBook.ACTIVE:
			continue
		if _has_choice(base, "complete_quest", id):
			continue
		var options: Array = q.get("options", [])
		if options.is_empty():
			out.append({"text": str(q.get("handoff", "건네기")), "action": "complete_quest", "arg": id})
		else:
			for i in options.size():
				out.append({"text": str(options[i]["text"]), "action": "complete_quest", "arg": "%s|%d" % [id, i]})
	if job != null and job.job_type == "deliver" and job.recipient == target:
		out.append({"text": "편지 전해 주기 (아르바이트)", "action": "job_deliver"})
	var offers: Array = []
	if not speaker.begins_with("obj:"):
		for id in data.quest_order:
			var q: Dictionary = data.quests[id]
			if str(q.get("giver", "")) == target and q.get("offer", "auto") == "auto" and quest_available(id) \
					and not _has_choice(base, "quest_offer", id):
				var prefix := "부탁 듣기: " if q.get("kind", "quest") == "quest" else "이야기 나누기: "
				offers.append({"text": prefix + str(q["name"]), "action": "quest_offer", "arg": id})
		if location == "card_room" and data.opponents.has(target) and target != str(poker_rules().get("opponent", "")) \
				and not _has_choice(base, "start_poker", ""):
			offers.append({"text": "한 판 할래요? (참가금 %d칩)" % poker_stake(), "action": "start_poker", "arg": "homegame|" + target})
	out.append_array(base)
	# Offers go before a trailing "close" so the goodbye stays last.
	var insert_at := out.size()
	if insert_at > 0 and out[insert_at - 1].get("action", "") == "close":
		insert_at -= 1
	for o in offers:
		out.insert(insert_at, o)
		insert_at += 1
	# Anything added to an entry without its own goodbye still gets a way out.
	if not out.is_empty() and base.size() < out.size() and not _has_choice(out, "close", ""):
		out.append({"text": "그만두기", "action": "close"})
	return out


func _has_choice(choices: Array, action: String, arg: String) -> bool:
	for c in choices:
		if c.get("action", "") == action and (arg == "" or str(c.get("arg", "")).get_slice("|", 0) == arg):
			return true
	return false


## "!" over a resident: a marked entry, something to hand over, a task to offer, or the letter.
func npc_has_news(npc_id: String, location: String) -> bool:
	if state == null:
		return false
	if resolve_entry(npc_id, location).get("marker", false):
		return true
	for id in data.quest_order:
		var q: Dictionary = data.quests[id]
		if str(q.get("target", "")) == npc_id and QuestBook.state_of(state, id) == QuestBook.ACTIVE:
			return true
		if str(q.get("giver", "")) == npc_id and q.get("offer", "auto") == "auto" and quest_available(id):
			return true
	return job != null and job.job_type == "deliver" and job.recipient == npc_id


# --- projects, home, shops --------------------------------------------------------

func project_status(pid: String) -> String:
	if state.project_done(pid):
		return "complete"
	return "available" if Conditions.check(data.projects[pid].get("unlock", {}), state) else "locked"


func fund_project(pid: String) -> Dictionary:
	if not data.projects.has(pid) or project_status(pid) != "available":
		return {"ok": false, "reason": "unavailable"}
	var p: Dictionary = data.projects[pid]
	var effects: Array = [
		{"type": "spend", "amount": int(p["cost"]), "reason": "project:" + pid},
		{"type": "project", "project": pid},
		{"type": "contribution", "id": "project:" + pid},
	]
	effects.append_array(p.get("effects", []))
	return run_effects(effects, "project:" + pid)


func home_stage_def(stage: int) -> Dictionary:
	for st in data.home.get("stages", []):
		if int(st["stage"]) == stage:
			return st
	return {}


func upgrade_home() -> Dictionary:
	var next := home_stage_def(state.home_stage + 1)
	if next.is_empty():
		return {"ok": false, "reason": "max"}
	if not Conditions.check(next.get("unlock", {}), state):
		return {"ok": false, "reason": "locked"}
	var effects: Array = [
		{"type": "spend", "amount": int(next["cost"]), "reason": "home:" + str(next["id"])},
		{"type": "home_stage", "stage": int(next["stage"])},
	]
	effects.append_array(next.get("effects", []))
	return run_effects(effects, "home:" + str(next["id"]))


## Items a shop offers right now (unlock conditions met).
func shop_items(shop_id: String) -> Array:
	var out: Array = []
	for entry in data.shops.get(shop_id, {}).get("items", []):
		if entry is String:
			out.append(entry)
		elif Conditions.check(entry.get("unlock", {}), state):
			out.append(entry["item"])
	return out


func item_on_sale(item_id: String) -> bool:
	for shop_id in data.shops:
		if shop_items(shop_id).has(item_id):
			return true
	return false


## Fixed single-player exchange at the swap stall: give owned items, get another. Once per trade.
func trade(trade_id: String) -> Dictionary:
	for t in data.trades:
		if t["id"] != trade_id:
			continue
		if state.events_done.has("trade:" + trade_id):
			return {"ok": false, "reason": "done"}
		var need := int(t.get("give_count", 1))
		if state.owned_count(t["give"]) < need:
			return {"ok": false, "reason": "missing"}
		var change := func() -> Dictionary:
			for i in need:
				state._take_from_storage(t["give"])
			state.grant_item(t["get"])
			state.events_done["trade:" + trade_id] = true
			return {"ok": true}
		return _commit(change)
	return {"ok": false, "reason": "unknown"}


## Which task the HUD follows (requests and episodes alike).
func track_quest(quest_id: String) -> bool:
	if QuestBook.state_of(state, quest_id) != QuestBook.ACTIVE:
		return false
	var change := func() -> Dictionary:
		state.tracked_quest = quest_id
		return {"ok": true}
	return _commit(change)["ok"]


func unequip(category: String) -> bool:
	var change := func() -> Dictionary: return {"ok": state.equipped.erase(category)}
	return _commit(change)["ok"]


func equip(item_id: String) -> bool:
	var item: Dictionary = data.items.get(item_id, {})
	var cat := str(item.get("category", ""))
	if not DataDB.EQUIP_CATEGORIES.has(cat) or state.owned_count(item_id) <= 0:
		return false
	var change := func() -> Dictionary:
		state.equipped[cat] = item_id
		return {"ok": true}
	return _commit(change)["ok"]


func item_color(item_id: String, fallback: Color) -> Color:
	var ph: Dictionary = data.items.get(item_id, {}).get("placeholder", {})
	return Color(str(ph["color"])) if ph.has("color") else fallback


## A short line on finishing a job that follows the story (content alpha).
func job_done_line(job_id: String) -> String:
	return str(data.jobs.get(job_id, {}).get("done_lines", {}).get(Conditions.current_act(state), ""))


## Readable name of a resident memory: a task name, or data/memories.json.
func memory_name(id: String) -> String:
	if data.quests.has(id):
		return str(data.quests[id]["name"])
	return str(data.memories.get(id, id))


## A line said when sitting down (content alpha): depends on the table and on the history with
## this opponent (first hand, after the player won, after the player lost, again). Public only.
func poker_opening(m: PokerMatch) -> String:
	var opp := match_opponent(m)
	var o: Dictionary = data.opponents.get(opp, {})
	var opens: Dictionary = o.get("open", {})
	var line := ""
	var hands := int(state.relation(opp)["poker_hands"])
	var hist: Array = state.poker_history.get(opp, [])
	if opens.has(m.mode) and hands > 0:
		line = str(opens[m.mode])
	elif hands == 0:
		line = str(opens.get("first", ""))
	elif not hist.is_empty() and str(hist[hist.size() - 1].get("outcome", "")) == "win":
		line = str(opens.get("after_player_win", opens.get("again", "")))
	elif not hist.is_empty() and str(hist[hist.size() - 1].get("outcome", "")) == "lose":
		line = str(opens.get("after_player_loss", opens.get("again", "")))
	else:
		line = str(opens.get("again", ""))
	var intro := str(poker_mode(m.mode).get("intro", ""))
	var said := "%s: \"%s\"" % [data.npc_name(opp), line] if line != "" else ""
	return " ".join([intro, said]).strip_edges()


## Extra result lines: one-time prizes and what the table remembers.
func poker_result_notes(m: PokerMatch, result: Dictionary) -> Array:
	var notes: Array = []
	var opp := match_opponent(m)
	if result.has("first_win_bonus"):
		notes.append("%s에게 처음 이겼어요! 기념 칩 +%d" % [data.npc_name(opp), int(result["first_win_bonus"])])
	if result.has("round_prize"):
		notes.append("대회 라운드 상금 +%d칩" % int(result["round_prize"]))
	var hands := int(state.relation(opp)["poker_hands"])
	if m.mode == "friendly_challenge" and hands > 1:
		notes.append("%s와의 %d번째 승부" % [data.npc_name(opp), hands])
	elif hands == 1 and m.mode != "practice":
		notes.append("%s와 처음 함께한 판이에요." % data.npc_name(opp))
	return notes


## "What can I do now?" (content alpha, 12 postgame): not a checklist, just where life continues.
func things_to_do() -> Array:
	var out: Array = []
	var news: Array = []
	for npc in data.npc_order:
		if not state.has_met(npc):
			continue
		for id in data.quest_order:
			var q: Dictionary = data.quests[id]
			if q.get("kind", "") == "episode" and str(q["giver"]) == npc and quest_available(id):
				news.append(data.npc_name(npc))
				break
	var unmet := data.npc_order.filter(func(n): return not state.has_met(n)).size()
	if unmet > 0:
		out.append("아직 인사하지 못한 이웃이 %d명 있어요." % unmet)
	if not news.is_empty():
		out.append("이야기를 들려줄 이웃: " + ", ".join(news.slice(0, 4)) + (" 외 %d명" % (news.size() - 4) if news.size() > 4 else ""))
	var reqs := data.quest_order.filter(func(id): return data.is_quest(id) and quest_available(id)).size()
	if reqs > 0:
		out.append("게시판에 새 부탁이 %d개 있어요." % reqs)
	var close := 0
	for npc in data.npc_order:
		if state.has_met(npc) and int(state.relation(npc)["friendship"]) < 30:
			close += 1
	if close > 0:
		out.append("더 가까워질 수 있는 이웃이 %d명 있어요. 이야기와 부탁, 방문이 쌓이면 달라져요." % close)
	var rivals: Array = []
	for npc in data.opponents:
		if int(state.relation(npc)["poker_hands"]) > 0 and int(state.relation(npc)["poker_hands"]) < 3:
			rivals.append(data.npc_name(npc))
	if not rivals.is_empty():
		out.append("다시 붙어 보자는 상대: " + ", ".join(rivals.slice(0, 3)))
	var left := data.project_order.size() - state.projects.size()
	if left > 0:
		out.append("회관 공공사업이 %d개 남아 있어요." % left)
	if not home_stage_def(state.home_stage + 1).is_empty():
		out.append("집을 %s(으)로 넓힐 수 있어요." % str(home_stage_def(state.home_stage + 1)["name"]))
	var found := state.collection.size()
	if found < data.item_order.size():
		out.append("수집 도감 %d / %d" % [found, data.item_order.size()])
	if state.get_flag("story.act3_complete"):
		out.append("네잎 저녁제는 저녁마다 광장 부스에서 다시 열 수 있어요." + ("" if state.tournament.get("rewarded", false) else " 대회 우승 기념품도 아직이에요."))
	if out.is_empty():
		out.append("마을은 오늘도 평소처럼 흘러가요. 가고 싶은 곳으로 가 보세요.")
	return out


## Village news for the notice board: the next story step and festival contributions.
func story_news() -> String:
	var lines: Array = []
	var f := func(flag: String) -> bool: return state.get_flag(flag)
	if not f.call("story.prologue_complete"):
		lines.append("[첫 저녁] 새 이웃이 왔어요. 집에 작은 등불을 놓으면 루미가 반가워할 거예요.")
	elif not f.call("story.act1_started"):
		lines.append("[1막 · 사라진 초대장] 모아가 카드룸 초대장이 사라졌다고 걱정하고 있어요.")
	elif not f.call("story.act1_complete"):
		lines.append("[1막 · 사라진 초대장] 단서 — 주거 골목 우편함: %s · 숲길 안내판: %s" % [
			"찾음" if f.call("story.clue_postbox") else "아직", "찾음" if f.call("story.clue_grove") else "아직"])
	elif not f.call("story.act2_complete"):
		lines.append("[2막 · 서로 다른 테이블] 루미 이야기: %s · 카일 이야기: %s · 모임 준비: %s" % [
			"들음" if f.call("story.act2_heard_lumi") else "아직", "들음" if f.call("story.act2_heard_kyle") else "아직",
			"끝남" if f.call("story.act2_prep_done") else "아직"])
	elif not f.call("story.act3_complete"):
		lines.append("[3막 · 네잎 저녁제] 준비 기여 %d / 3%s" % [state.contributions.size(),
			" — 회관 주민 회의가 열려요" if state.contributions.size() >= 3 and not f.call("story.festival_ready") else ""])
		for c in state.contributions:
			lines.append("  ✔ " + contribution_name(str(c)))
		if f.call("story.festival_ready"):
			lines.append("축제 준비 완료! 저녁에 광장 축제 부스로 오세요.")
	else:
		lines.append("[후일담] 네잎 저녁제가 끝났어요. 광장 축제 부스에서 언제든 다시 즐길 수 있어요.")
	lines.append("공공사업 %d / %d 완료 · 집: %s" % [state.projects.size(), data.project_order.size(),
		home_stage_def(state.home_stage).get("name", "작은 방")])
	return "
".join(lines)


## Readable name of a festival contribution key ("prep:juno", "quest:<id>", "project:<id>", "poker:first").
func contribution_name(key: String) -> String:
	var kind := key.get_slice(":", 0)
	var id := key.substr(kind.length() + 1)
	match kind:
		"quest":
			return "의뢰 · " + str(data.quests.get(id, {}).get("name", id))
		"project":
			return "공공사업 · " + str(data.projects.get(id, {}).get("name", id))
		"poker":
			return "축제 준비 기간의 첫 포커 모임"
		"prep":
			return {"juno": "주노와 장식 달기", "spectate": "모아와 관전 자리 정리"}.get(id, "축제 준비 돕기")
	return key
