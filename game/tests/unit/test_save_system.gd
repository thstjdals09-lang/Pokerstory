extends "res://tests/test_case.gd"

const PATH := "user://unit_test_save.json"


func _write_raw(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_save_and_load_round_trip() -> void:
	SaveSystem.delete(PATH)
	var s := GameState.new()
	s.player_name = "세이브"
	s.add_chips(70, "t")
	s.set_flag("first_poker_bonus_claimed")
	check_eq(SaveSystem.save(s, PATH), OK, "save ok")
	var r := SaveSystem.load_state(PATH)
	check(r["ok"], "load ok")
	check_eq(r["state"].to_dict(), s.to_dict(), "same content")
	check(not FileAccess.file_exists(PATH + ".tmp"), "no temp file left")
	SaveSystem.save(s, PATH)
	check(FileAccess.file_exists(PATH + ".bak"), "previous save kept as backup")
	SaveSystem.delete(PATH)


func test_missing_save() -> void:
	SaveSystem.delete(PATH)
	check_eq(SaveSystem.load_state(PATH)["error"], "no_save", "missing file")


func test_newer_version_is_rejected_and_file_untouched() -> void:
	var text := '{"save_version": 999, "player_name": "미래", "chips_balance": 5}'
	_write_raw(text)
	var r := SaveSystem.load_state(PATH)
	check(not r["ok"], "rejected")
	check_eq(r["error"], "too_new", "error code")
	check(str(r["message"]).contains("새로운 버전"), "message explains")
	check_eq(FileAccess.get_file_as_string(PATH), text, "file not modified")
	SaveSystem.delete(PATH)


func test_older_unsupported_version_is_rejected() -> void:
	_write_raw('{"save_version": 0, "chips_balance": 5}')
	check_eq(SaveSystem.load_state(PATH)["error"], "unsupported_old", "old version")
	SaveSystem.delete(PATH)


func test_corrupt_file_is_rejected() -> void:
	_write_raw("{ this is not json")
	check_eq(SaveSystem.load_state(PATH)["error"], "corrupt", "bad json")
	_write_raw('{"chips_balance": 5}')
	check_eq(SaveSystem.load_state(PATH)["error"], "corrupt", "missing version")
	SaveSystem.delete(PATH)
