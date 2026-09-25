class_name PlazaJob
extends RefCounted
## One run of a repeatable odd job (data/jobs.json): pick up `count` scattered cards and chips
## at different spots. Each spot can be collected once, and the reward is paid only after the
## last one, so pressing the interact key in one place never earns chips.
## A run is not saved: leaving the area or quitting cancels it without reward.

var job_id := ""
var reward := 0
## spot_id -> {"pos": Vector2, "kind": "card" | "chip"}
var spots := {}
var collected := {}
var rewarded := false


static func create(job: Dictionary, rng: RandomNumberGenerator) -> PlazaJob:
	var run := PlazaJob.new()
	run.job_id = job["id"]
	run.reward = int(job.get("reward", 0))
	var pool: Array = job.get("spots", [])
	var order: Array = range(pool.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var count := mini(int(job.get("count", 5)), pool.size())
	for n in count:
		var idx: int = order[n]
		run.spots["spot_%d" % idx] = {
			"pos": Geo.vec(pool[idx]),
			"kind": "card" if n % 2 == 0 else "chip",
		}
	return run


func total() -> int:
	return spots.size()


func remaining() -> Array:
	var out: Array = []
	for id in spots:
		if not collected.has(id):
			out.append(id)
	return out


## Collects one spot and, when it was the last one, pays the reward into `state` exactly once.
## Returns {"ok": bool, "collected": n, "total": n, "done": bool, "reward": n};
## ok is false for an unknown or already collected spot (nothing changes).
func collect(state: GameState, spot_id: String) -> Dictionary:
	if rewarded or not spots.has(spot_id) or collected.has(spot_id):
		return {"ok": false}
	collected[spot_id] = true
	var result := {"ok": true, "collected": collected.size(), "total": total(), "done": false, "reward": 0}
	if is_complete():
		rewarded = true
		state.add_chips(reward, "job:" + job_id)
		state.jobs_completed += 1
		result["done"] = true
		result["reward"] = reward
	return result


func is_complete() -> bool:
	return not spots.is_empty() and collected.size() == spots.size()
