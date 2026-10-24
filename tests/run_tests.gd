extends SceneTree
## Headless test runner. From the "My project" folder:
##   Godot_v4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path sudoku-pop --script res://tests/run_tests.gd

const SUITES := [
	"res://tests/test_board.gd",
	"res://tests/test_piece.gd",
	"res://tests/test_rules.gd",
	"res://tests/test_scoring.gd",
	"res://tests/test_game_state.gd",
	"res://tests/test_records.gd",
	"res://tests/test_simulation.gd",
	"res://tests/test_chess.gd",
	"res://tests/test_dice.gd",
	"res://tests/test_flip.gd",
	"res://tests/test_fleet.gd",
	"res://tests/test_grid.gd",
]


## GDScript has no exceptions: a script error just abandons the function.
## Counting logged errors is how a crashing test gets marked as failed.
class ErrorCounter:
	extends Logger
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		count += 1


func _initialize() -> void:
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
	var passed := 0
	var failed := 0
	for path: String in SUITES:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failed += 1
			print("FAIL %s :: does not compile" % path.get_file())
			continue
		var suite: RefCounted = script.new()
		for method in suite.get_method_list():
			var test_name: String = method.name
			if not test_name.begins_with("test_"):
				continue
			suite.failures.clear()
			var errors_before := errors.count
			suite.call(test_name)
			if errors.count > errors_before:
				suite.failures.append("script error (see log above)")
			if suite.failures.is_empty():
				passed += 1
			else:
				failed += 1
				print("FAIL %s :: %s" % [path.get_file(), test_name])
				for f: String in suite.failures:
					print("    ", f)
	OS.remove_logger(errors)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
