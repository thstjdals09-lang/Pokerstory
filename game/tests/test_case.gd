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


## Talks to a speaker and picks the first choice whose text contains `pick` (or the first choice),
## applying entry and choice effects the way main.gd does. Follows "dialogue" chains.
## Returns the ids of the entries shown.
func talk(db: DataDB, s: GameState, speaker: String, location: String, picks: Array = []) -> Array:
	var shown: Array = []
	var entry := DialogueResolver.resolve(db.dialogue, speaker, location, s)
	var queue := picks.duplicate()
	while not entry.is_empty() and shown.size() < 8:
		shown.append(entry["id"])
		var eff: Array = []
		for f in entry.get("set_flags", []):
			eff.append({"type": "flag", "flag": f})
		eff.append_array(entry.get("effects", []))
		Effects.apply(s, eff, DialogueResolver.once_key(entry) if entry.get("once", false) else "")
		var choices: Array = entry.get("choices", []).filter(
			func(c): return Conditions.check(c.get("conditions", {}), s, location))
		if choices.is_empty():
			break
		var want: String = queue.pop_front() if not queue.is_empty() else ""
		var chosen: Dictionary = choices[0]
		for c in choices:
			if want != "" and str(c["text"]).contains(want):
				chosen = c
				break
		Effects.apply(s, chosen.get("effects", []), str(chosen.get("once_key", "")))
		if chosen.get("action", "") == "dialogue":
			entry = DialogueResolver.find(db.dialogue, chosen["arg"])
		else:
			entry = {}
	return shown
