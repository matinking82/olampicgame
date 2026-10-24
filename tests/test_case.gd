extends RefCounted
## Base for test suites: methods named test_* are run by run_tests.gd.

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])


## Compares two lists of cells, ignoring order.
func check_cells(actual: Array, expected: Array, message: String = "") -> void:
	var a := actual.duplicate()
	var e := expected.duplicate()
	a.sort()
	e.sort()
	if str(a) != str(e):
		failures.append("%s: expected cells %s, got %s" % [message, str(e), str(a)])


static func v(x: int, y: int) -> Vector2i:
	return Vector2i(x, y)


static func mono(value: int) -> Piece:
	return Piece.make([Vector2i(0, 0)], [value])


static func domino(a: int, b: int) -> Piece:
	return Piece.make([Vector2i(0, 0), Vector2i(1, 0)], [a, b])
