class_name Prof
## Poor man's profiler for the perf scripts. `Prof.on` is false in the game; tests/perf_battle.gd turns it on. Call sites look like
##   var p0 := Time.get_ticks_usec() if Prof.on else 0     ...     if Prof.on: Prof.add("enemy.sense", p0)
## Sections nest (enemy.tick contains enemy.sense...), so the sums are per section, not additive.

static var on := false
static var usec := {}
static var calls := {}


static func add(section: String, t0: int) -> void:
	usec[section] = int(usec.get(section, 0)) + Time.get_ticks_usec() - t0
	calls[section] = int(calls.get(section, 0)) + 1


static func reset() -> void:
	usec.clear()
	calls.clear()
