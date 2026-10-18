class_name AiBudget
## Global per-tick budget for the expensive things the soldiers and civilians do: physics rays (senses, line of sight, threat scans)
## and A* path requests. Main calls `new_tick()` once per physics tick; an agent that is refused simply tries again next tick, and
## because the agents that were served reset their own timers, the refused ones get the next free slots (a natural round robin).
## Counters (`rays_total`, `rays_denied`, ...) are for the perf tools.

const RAYS_PER_TICK := 12          # at 120 ticks/s: 1440 AI rays per second at most (the player's weapons are not counted)
const PATHS_PER_TICK := 1          # A* requests per tick (agents keep following their old path while they wait)

static var rays := 0
static var paths := 0
static var rays_total := 0
static var rays_denied := 0
static var paths_total := 0
static var paths_denied := 0


static func new_tick() -> void:
	rays = 0
	paths = 0


## True if an AI ray may be cast now (and counts it).
static func ray() -> bool:
	if rays >= RAYS_PER_TICK:
		rays_denied += 1
		return false
	rays += 1
	rays_total += 1
	return true


## True if an A* request may be made now (and counts it).
static func path() -> bool:
	if paths >= PATHS_PER_TICK:
		paths_denied += 1
		return false
	paths += 1
	paths_total += 1
	return true


static func reset_counters() -> void:
	rays_total = 0
	rays_denied = 0
	paths_total = 0
	paths_denied = 0
