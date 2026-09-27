class_name BattleState
extends RefCounted

const TICK_RATE := 30
var tick := 0
var time_elapsed := 0.0
var time_limit := 90.0
var tactical_gauge := 3.0
var wave := 0
var wave_count := 0
var ended := false
var victory := false
var reason := ""
var party: Array = []
var enemies: Array = []
## Cover cells ([col, lane]) of this stage and the party's focus-fire target.
var cover_cells: Array = []
var focus_uid := ""

