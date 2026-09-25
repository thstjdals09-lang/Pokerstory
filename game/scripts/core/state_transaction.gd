class_name StateTransaction
extends RefCounted
## "Change + save" as one unit (content v0.3.1). Every persistent change (chips, purchases, trades,
## projects, house, placements, quest and job rewards, poker stakes and settlements, one-time event
## rewards) runs through here: the state is snapshotted, the change is applied, the game is saved,
## and if the save fails the state is put back exactly as it was. So a failed save never leaves a
## reward paid in memory only, a purchase without payment, lost chips or a completion flag alone;
## the player simply does the action again.
##
## `change` returns a Dictionary with "ok" (a refused change must not have touched the state) and
## optionally "skipped": true when nothing persistent changed (nothing to save).
## `save` returns true when the save succeeded.


static func run(state: GameState, change: Callable, save: Callable) -> Dictionary:
	var before := state.to_dict()
	var result = change.call()
	var r: Dictionary = result if result is Dictionary else {"ok": bool(result)}
	if not r.get("ok", false) or r.get("skipped", false):
		return r
	if not bool(save.call()):
		state.restore(before)
		var failed := r.duplicate()
		failed["ok"] = false
		failed["reason"] = "save_failed"
		return failed
	return r
