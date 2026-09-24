extends SceneTree
## Headless unit test runner.
##   godot --headless --path game -s res://tests/run_tests.gd
## Exit code 0 = all passed, 1 = at least one failure.

const UNIT_DIR := "res://tests/unit"


func _initialize() -> void:
	var total := 0
	var failed := 0
	var files := Array(DirAccess.get_files_at(UNIT_DIR))
	files.sort()
	for file in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var script: GDScript = load(UNIT_DIR + "/" + file)
		var suite = script.new()
		for m in suite.get_method_list():
			var method: String = m["name"]
			if not method.begins_with("test_"):
				continue
			suite.failures = []
			suite.call(method)
			total += 1
			if suite.failures.is_empty():
				print("  ok    %s :: %s" % [file, method])
			else:
				failed += 1
				print("  FAIL  %s :: %s" % [file, method])
				for f in suite.failures:
					print("          - " + str(f))
	print("\n%d tests, %d passed, %d failed" % [total, total - failed, failed])
	quit(1 if failed > 0 else 0)
