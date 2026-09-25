class_name PlazaJob
extends RefCounted
## One run of a repeatable odd job (data/jobs.json). Types:
##   collect  pick up `count` items at different spots (plaza clean-up, lantern check)
##   deliver  take a letter to the recipient of this run (recipients rotate)
##   shelve   put the right goods on `count` shelves, one shelf at a time
## Each step counts once and the reward is paid only when the whole run is done, so repeating
## one interaction never earns chips. A run is not saved: leaving or quitting cancels it unpaid.

var job_id := ""
var job_type := "collect"
var reward := 0
var run_number := 0
## collect: spot_id -> {"pos": Vector2, "kind": "card" | "chip" | "lantern"}
var spots := {}
var collected := {}
## deliver
var recipient := ""
## shelve: expected good per shelf, in order
var shelf_goods: Array = []
var rewarded := false


static func create(job: Dictionary, rng: RandomNumberGenerator, p_run_number: int = 1) -> PlazaJob:
	var run := PlazaJob.new()
	run.job_id = job["id"]
	run.job_type = str(job.get("type", "collect"))
	run.reward = int(job.get("reward", 0))
	run.run_number = p_run_number
	match run.job_type:
		"collect":
			var pool: Array = job.get("spots", [])
			var order: Array = range(pool.size())
			for i in range(order.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var tmp = order[i]
				order[i] = order[j]
				order[j] = tmp
			var count := mini(int(job.get("count", 5)), pool.size())
			var kinds: Array = job.get("pickup_kinds", ["card", "chip"])
			for n in count:
				var idx: int = order[n]
				run.spots["spot_%d" % idx] = {"pos": Geo.vec(pool[idx]), "kind": kinds[n % kinds.size()]}
		"deliver":
			var recipients: Array = job.get("recipients", [])
			run.recipient = recipients[(p_run_number - 1) % recipients.size()]
		"shelve":
			var goods: Array = job.get("goods", []).duplicate()
			for i in range(goods.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var tmp = goods[i]
				goods[i] = goods[j]
				goods[j] = tmp
			run.shelf_goods = goods.slice(0, int(job.get("count", 3)))
	return run


func total() -> int:
	match job_type:
		"deliver":
			return 1
		"shelve":
			return shelf_goods.size()
	return spots.size()


func done_count() -> int:
	return collected.size()


func remaining() -> Array:
	var out: Array = []
	for id in spots:
		if not collected.has(id):
			out.append(id)
	return out


## collect: picks up one spot. Returns the step result (see _step).
func collect(state: GameState, spot_id: String) -> Dictionary:
	if job_type != "collect" or rewarded or not spots.has(spot_id) or collected.has(spot_id):
		return {"ok": false}
	return _step(state, spot_id)


## deliver: hands the letter to `npc_id` if it is this run's recipient.
func deliver(state: GameState, npc_id: String) -> Dictionary:
	if job_type != "deliver" or rewarded or npc_id != recipient:
		return {"ok": false}
	return _step(state, "delivered")


## shelve: the next empty shelf must get its expected good; a wrong good changes nothing.
func shelve(state: GameState, good: String) -> Dictionary:
	if job_type != "shelve" or rewarded:
		return {"ok": false}
	var shelf := collected.size()
	if shelf >= shelf_goods.size() or shelf_goods[shelf] != good:
		return {"ok": false, "wrong": true}
	return _step(state, "shelf_%d" % shelf)


## The good the next empty shelf needs (shelve), or "".
func next_shelf_good() -> String:
	return shelf_goods[collected.size()] if job_type == "shelve" and collected.size() < shelf_goods.size() else ""


func is_complete() -> bool:
	return total() > 0 and collected.size() >= total()


func _step(state: GameState, step_id: String) -> Dictionary:
	collected[step_id] = true
	var result := {"ok": true, "collected": collected.size(), "total": total(), "done": false, "reward": 0}
	if is_complete():
		rewarded = true
		state.add_chips(reward, "job:%s:%d" % [job_id, run_number])
		state.jobs_completed += 1
		result["done"] = true
		result["reward"] = reward
	return result
