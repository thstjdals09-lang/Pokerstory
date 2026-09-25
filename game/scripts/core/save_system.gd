class_name SaveSystem
extends RefCounted
## Single-slot JSON save with a version field.
## Writes go to <path>.tmp first, the previous save is kept as <path>.bak, then the tmp file
## replaces the save, so a crash mid-write never destroys the last good save.


static func save(state: GameState, path: String) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(state.to_dict(), "  "))
	f.close()
	var bak := path + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		var err := DirAccess.rename_absolute(path, bak)
		if err != OK:
			return err
	return DirAccess.rename_absolute(tmp, path)


## Returns {"ok": true, "state": GameState, "original_version": n, "legacy_stake": bool}
## or {"ok": false, "error": code, "message": text}.
## Error codes: no_save, corrupt, too_new, unsupported_old. A rejected file is never modified.
static func load_state(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("no_save", "저장된 게임이 없어요.")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("save_version"):
		return _fail("corrupt", "저장 파일을 읽을 수 없어요. 파일이 손상되었을 수 있어요.")
	var version := int(parsed["save_version"])
	var original_version := version
	if version > GameState.SAVE_VERSION:
		return _fail("too_new", "이 저장 파일은 더 새로운 버전의 게임에서 만들어졌어요 (저장 v%d, 현재 게임은 v%d까지 읽을 수 있어요)." % [version, GameState.SAVE_VERSION])
	while version < GameState.SAVE_VERSION:
		var next := _migrate(parsed, version)
		if next.is_empty():
			return _fail("unsupported_old", "이 저장 파일(v%d)은 지원하지 않는 이전 버전이에요." % version)
		parsed = next
		version = int(parsed["save_version"])
	var state := GameState.from_dict(parsed)
	# An unfinished hand must restore exactly; otherwise the save is treated as damaged
	# rather than inventing a refund.
	if not state.poker_in_progress.is_empty() and PokerMatch.from_dict(state.poker_in_progress) == null:
		return _fail("corrupt", "저장된 진행 중 포커 판을 복원할 수 없어요. 파일이 손상되었을 수 있어요.")
	# A paid stake without saved cards is only possible in saves written before v3 (the stake and the
	# cards are saved together since then). Design Review 04, R2: only such old saves get a one-time
	# replacement hand; a v3 save in that state is damaged.
	var legacy_stake := state.pending_poker_stake > 0 and state.poker_in_progress.is_empty()
	if legacy_stake and original_version >= 3:
		return _fail("corrupt", "저장된 진행 중 포커 판을 찾을 수 없어요. 파일이 손상되었을 수 있어요.")
	return {"ok": true, "state": state, "original_version": original_version, "legacy_stake": legacy_stake}


static func delete(path: String) -> void:
	for p in [path, path + ".tmp", path + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## Upgrades a save dictionary by one version. Add a case here whenever SAVE_VERSION increases.
## Returns an empty dictionary when no migration exists.
static func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	match from_version:
		1:
			# v1 -> v2 (Design Correction 02): time of day, quests, pending stake.
			# The chip balance is kept as it is; the new-game starting chips never apply to old saves.
			var d := data.duplicate(true)
			d["save_version"] = 2
			d["time_of_day"] = "evening" if str(d.get("current_scene", "")) == "card_room" else "day"
			d["quests"] = {}
			d["pending_poker_stake"] = 0
			d["jobs_completed"] = 0
			return d
		2:
			# v2 -> v3 (Design Review 03): unfinished hands are saved instead of refunded.
			var d := data.duplicate(true)
			d["save_version"] = 3
			d["poker_in_progress"] = {}
			return d
		3:
			# v3 -> v4 (content v0.3): residents, projects, housing stage, story. Everything saved
			# before is kept; residents the player already met keep that fact.
			var d := data.duplicate(true)
			d["save_version"] = 4
			var flags: Dictionary = d.get("flags", {})
			var rels := {}
			for pair in [["npc_lumi", "intro_met_lumi"], ["npc_moa", "moa_met"], ["npc_sera", "sera_met"]]:
				if bool(flags.get(pair[1], false)):
					rels[pair[0]] = {"met": true, "friendship": 5, "rivalry": 0, "poker_hands": 0, "memories": [],
						"romance": {"consent": false, "stage": "closed", "seen_dates": []}}
			d["relations"] = rels
			# A player who already saw Lumi's lamp reaction finished the prologue (story.prologue_complete
			# is set by that same scene now), so the main story can start without replaying it.
			if bool(flags.get("lumi_lamp_reaction_seen", false)):
				flags["story.prologue_complete"] = true
				d["flags"] = flags
			d["npc_edges"] = {}
			d["projects"] = {}
			d["home_stage"] = 0
			d["events_done"] = {}
			d["contributions"] = []
			d["equipped"] = {}
			d["abilities_unlocked"] = ["ability.star_sense"]
			d["poker_history"] = {}
			d["tournament"] = {"stage": 0, "rewarded": false}
			d["tracked_quest"] = ""
			return d
	return {}


static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}
