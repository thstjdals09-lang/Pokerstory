extends RefCounted
## Base class for unit test suites. Methods named test_* are run by tests/run_tests.gd.

var failures: Array = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual, expected, message: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: expected <%s> got <%s>" % [message, str(expected), str(actual)])


## Builds a hand from codes like "AS KD 7C 7H 2S".
func hand(codes: String) -> Array:
	var cards: Array = []
	for c in codes.split(" ", false):
		cards.append(Card.from_code(c))
	return cards
