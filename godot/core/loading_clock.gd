extends RefCounted

## Loading deadlines and per-frame work budgets that follow the frames a browser
## actually delivers.
##
## A hidden tab, a battery-saver throttle or a very slow phone hands the game one
## frame every few hundred milliseconds. Two fixed numbers then break first map
## entry: a wall-clock "no progress for 12 s" watchdog fires while the tab was
## simply not being drawn, and a fixed ten-millisecond work slice per frame turns a
## three-second build into hundreds of mandatory frames. This class counts at most
## `MAX_STEP_MSEC` of loading time per tick and sizes work slices from the measured
## frame interval, so neither depends on how often the browser paints.

const MAX_STEP_MSEC := 250
# Twenty milliseconds keeps a loading screen at roughly 35 fps while halving the number
# of mandatory frames a build needs compared with the old fixed ten-millisecond slice.
const BASE_SLICE_USEC := 20000
const MAX_SLICE_USEC := 250000

## Loading time that has passed, counting at most `MAX_STEP_MSEC` for each tick.
var elapsed_msec := 0
## `elapsed_msec` at the last reported progress.
var last_progress_msec := 0
var _last_wall_msec := 0


func _init() -> void:
	_last_wall_msec = Time.get_ticks_msec()


## Advance once per loop pass and return the loading time in milliseconds.
func tick() -> int:
	var now := Time.get_ticks_msec()
	elapsed_msec += capped_step(now - _last_wall_msec)
	_last_wall_msec = now
	return elapsed_msec


func mark_progress() -> void:
	tick()
	last_progress_msec = elapsed_msec


## Pass `hard_msec` and `idle_msec` (no progress) in loading time.
func expired(hard_msec: int, idle_msec: int) -> bool:
	tick()
	return elapsed_msec >= hard_msec or elapsed_msec - last_progress_msec >= idle_msec


static func capped_step(wall_step_msec: int) -> int:
	return clampi(wall_step_msec, 0, MAX_STEP_MSEC)


## Work allowed in one slice: at most half of the last measured frame interval,
## never below the 20 ms floor.
static func slice_budget_usec(frame_interval_usec: int) -> int:
	return clampi(frame_interval_usec / 2, BASE_SLICE_USEC, MAX_SLICE_USEC)
