class_name BattleGrid
extends RefCounted

## The tactical battlefield: 3 lanes x 6 columns.
## Columns 0-2 belong to the party (0 = back row, 2 = front row) and columns 3-5
## to the enemy (3 = front row, 5 = back row). Lane 0 is the far lane on screen.
## Every unit stands on one cell; placement decides who can reach whom, who
## blocks an enemy's advance, who gets hit by an area attack and which
## positional bonuses apply.
const LANES := 3
const COLUMNS := 6
const PLAYER_COLUMNS := [0, 1, 2]
const ENEMY_COLUMNS := [3, 4, 5]
const PLAYER_FRONT := 2
const ENEMY_FRONT := 3

## Reach in columns. Melee reach counts lanes too (orthogonal steps), so a
## front-row blocker only covers its own lane; ranged reach ignores lanes.
const PLAYER_ROLE_REACH := {
	"GUARDIAN": {"range": 1, "melee": true},
	"VANGUARD": {"range": 2, "melee": true},
	"ASSAULT": {"range": 3, "melee": false},
	"SPECIALIST": {"range": 3, "melee": false},
	"ARTILLERY": {"range": 4, "melee": false},
	"MEDIC": {"range": 3, "melee": false},
}
## `step` is seconds per column while advancing; 0 never moves.
const ENEMY_ROLE_REACH := {
	"MELEE_RUSH": {"range": 1, "melee": true, "step": .9},
	"DEFENDER": {"range": 1, "melee": true, "step": 1.5},
	"RANGED": {"range": 3, "melee": false, "step": 1.2},
	"DEBUFFER": {"range": 3, "melee": false, "step": 1.2},
	"HEALER": {"range": 3, "melee": false, "step": 1.4},
	"BUFFER": {"range": 3, "melee": false, "step": 1.4},
	"SUMMONER": {"range": 3, "melee": false, "step": 1.4},
	"AREA": {"range": 3, "melee": false, "step": 1.3},
	"ARTILLERY": {"range": 5, "melee": false, "step": 1.6},
	"BOSS_PATTERN": {"range": 5, "melee": false, "step": 0.0},
}
const ENEMY_ROLE_COLUMN := {
	"MELEE_RUSH": 3, "DEFENDER": 3,
	"RANGED": 4, "DEBUFFER": 4, "AREA": 4, "SUMMONER": 4, "BOSS_PATTERN": 4,
	"HEALER": 5, "BUFFER": 5, "ARTILLERY": 5,
}
const POSITION_COLUMN := {"FRONT": 2, "MIDDLE": 1, "BACK": 0}
const ROLE_LABELS := {
	"GUARDIAN": "수호", "VANGUARD": "돌격", "ASSAULT": "사격", "SPECIALIST": "전술",
	"ARTILLERY": "포격", "MEDIC": "의료",
	"MELEE_RUSH": "돌진형", "DEFENDER": "방어형", "RANGED": "사격형", "DEBUFFER": "교란형",
	"HEALER": "수복형", "BUFFER": "강화형", "SUMMONER": "지휘형", "AREA": "광역형",
	"ARTILLERY_ENEMY": "포격형", "BOSS_PATTERN": "거대 반응",
}

# --- Positional modifiers ----------------------------------------------------
const COVER_DAMAGE_TAKEN := .70          # ranged hits on a unit in cover
const GUARDIAN_COVER_DAMAGE_TAKEN := .85  # allies orthogonally next to a guardian
const FLANK_DAMAGE := 1.30               # melee from the side or from behind
const SPECIALIST_AURA_DAMAGE := 1.10     # allies orthogonally next to a specialist
const ARTILLERY_BACK_ROW_DAMAGE := 1.15  # player artillery firing from column 0
const VANGUARD_FRONT_ROW_DAMAGE := 1.10  # player vanguard on column 2
const MEDIC_ADJACENT_HEAL := 1.25        # heals on a unit next to the medic

static func cell(col: int, lane: int) -> Array:
	return [col, lane]

static func key(col: int, lane: int) -> String:
	return "%d:%d" % [col, lane]

static func in_bounds(col: int, lane: int) -> bool:
	return col >= 0 and col < COLUMNS and lane >= 0 and lane < LANES

static func in_player_zone(col: int, lane: int) -> bool:
	return col >= 0 and col <= PLAYER_FRONT and lane >= 0 and lane < LANES

static func manhattan(a: Dictionary, b: Dictionary) -> int:
	return absi(int(a.get("col", 0)) - int(b.get("col", 0))) + absi(int(a.get("lane", 0)) - int(b.get("lane", 0)))

static func adjacent(a: Dictionary, b: Dictionary) -> bool:
	return manhattan(a, b) == 1

static func player_reach(role: String) -> Dictionary:
	return PLAYER_ROLE_REACH.get(role, {"range": 3, "melee": false})

static func enemy_reach(role: String, rank: String) -> Dictionary:
	if rank == "BOSS":
		return ENEMY_ROLE_REACH.BOSS_PATTERN
	return ENEMY_ROLE_REACH.get(role, {"range": 3, "melee": false, "step": 1.2})

static func role_label(role: String, team: String) -> String:
	if role == "ARTILLERY" and team == "ENEMY":
		return str(ROLE_LABELS.ARTILLERY_ENEMY)
	return str(ROLE_LABELS.get(role, role))

## Default placement from each member's preferred position: FRONT on column 2,
## MIDDLE on 1, BACK on 0, filling the middle lane first. A full column spills
## to the nearest free column.
static func default_formation(party: Array) -> Dictionary:
	var occupied: Dictionary = {}
	var output: Dictionary = {}
	var lane_order := [1, 0, 2]
	for member in party:
		var def_id := str(member.get("id", member.get("def_id", "")))
		var preferred := int(POSITION_COLUMN.get(str(member.get("preferred_position", "MIDDLE")), 1))
		var columns := [preferred]
		for offset in [1, -1, 2, -2]:
			var candidate: int = preferred + offset
			if candidate >= 0 and candidate <= PLAYER_FRONT and not columns.has(candidate):
				columns.append(candidate)
		var placed := false
		for col in columns:
			for lane in lane_order:
				if occupied.has(key(col, lane)): continue
				occupied[key(col, lane)] = true
				output[def_id] = [col, lane]
				placed = true
				break
			if placed: break
	return output

## Validated cells for the party in snapshot order. Invalid, duplicate or
## missing entries fall back to the default layout's free cells.
static func resolve_player_cells(party: Array, formation: Dictionary) -> Array:
	var cells: Array = []
	var occupied: Dictionary = {}
	for member in party:
		var def_id := str(member.get("id", member.get("def_id", "")))
		var wanted = formation.get(def_id, null)
		var accepted := false
		if wanted is Array and (wanted as Array).size() >= 2:
			var col := int(wanted[0])
			var lane := int(wanted[1])
			if in_player_zone(col, lane) and not occupied.has(key(col, lane)):
				occupied[key(col, lane)] = true
				cells.append([col, lane])
				accepted = true
		if not accepted:
			cells.append([])
	var fallback := default_formation(party)
	for index in range(party.size()):
		if not (cells[index] as Array).is_empty(): continue
		var def_id := str(party[index].get("id", party[index].get("def_id", "")))
		var preferred: Array = fallback.get(def_id, [1, 1])
		var col := int(preferred[0])
		var lane := int(preferred[1])
		if occupied.has(key(col, lane)):
			var free := first_free_player_cell(occupied, col)
			col = int(free[0])
			lane = int(free[1])
		occupied[key(col, lane)] = true
		cells[index] = [col, lane]
	return cells

static func first_free_player_cell(occupied: Dictionary, preferred_col: int) -> Array:
	var columns := [preferred_col, preferred_col - 1, preferred_col + 1, preferred_col - 2, preferred_col + 2]
	for col in columns:
		if col < 0 or col > PLAYER_FRONT: continue
		for lane in [1, 0, 2]:
			if not occupied.has(key(col, lane)):
				return [col, lane]
	return [0, 1]

## Enemy placement for one wave: the role decides the column and a per-stage
## lane order spreads the squad. A full column spills backwards (front roles)
## or forwards (rear roles). The boss always holds the centre of column 4.
static func enemy_cells(enemy_defs: Array, stage_id: String, wave_index: int) -> Array:
	var occupied: Dictionary = {}
	var cells: Array = []
	for _index in range(enemy_defs.size()):
		cells.append([])
	var seed := absi(hash("%s:%d:formation" % [stage_id, wave_index]))
	var orders := [[1, 0, 2], [0, 2, 1], [2, 0, 1], [1, 2, 0], [0, 1, 2], [2, 1, 0]]
	var lane_order: Array = orders[seed % orders.size()]
	# Bosses first so their centre cell is never taken by an escort.
	for index in range(enemy_defs.size()):
		if str(enemy_defs[index].get("rank", "")) != "BOSS": continue
		var lane := 1 if not occupied.has(key(4, 1)) else int(lane_order[index % 3])
		occupied[key(4, lane)] = true
		cells[index] = [4, lane]
	var cursor := 0
	for index in range(enemy_defs.size()):
		if not (cells[index] as Array).is_empty(): continue
		var definition: Dictionary = enemy_defs[index]
		var preferred := int(ENEMY_ROLE_COLUMN.get(str(definition.get("role", "RANGED")), 4))
		var columns := [preferred]
		for candidate in ([4, 5, 3] if preferred == 3 else ([5, 3] if preferred == 4 else [4, 3])):
			if not columns.has(candidate): columns.append(candidate)
		var placed := false
		for col in columns:
			for step in range(3):
				var lane := int(lane_order[(cursor + step) % 3])
				if occupied.has(key(col, lane)): continue
				occupied[key(col, lane)] = true
				cells[index] = [col, lane]
				placed = true
				cursor += 1
				break
			if placed: break
		if not placed:
			cells[index] = [5, 1]
	return cells

## Cover positions for a stage: one or two on the party side, up to two on the
## enemy side. The first two tutorial operations stay open ground.
static func cover_cells(stage: Dictionary) -> Array:
	var stage_id := str(stage.get("id", ""))
	var number := int(stage.get("stage_number", 1))
	var chapter := int(str(stage.get("chapter_id", "CH01")).substr(2))
	if chapter <= 1 and str(stage.get("mode", "NORMAL")) == "NORMAL" and number <= 2:
		return []
	var seed := absi(hash("%s:cover" % stage_id))
	var output: Array = []
	var player_col := seed % 2
	var player_lane := (seed / 2) % 3
	output.append([player_col, player_lane])
	if (seed / 7) % 3 != 0:
		output.append([1 - player_col, (player_lane + 1 + (seed / 11) % 2) % 3])
	var enemy_count := 1 + (seed / 13) % 2
	for index in range(enemy_count):
		var col := 3 + ((seed / (17 + index * 5)) % 2)
		var lane := (seed / (19 + index * 7)) % 3
		var candidate := [col, lane]
		if not output.has(candidate):
			output.append(candidate)
	return output

static func has_cell(cells: Array, col: int, lane: int) -> bool:
	for entry in cells:
		if int(entry[0]) == col and int(entry[1]) == lane:
			return true
	return false

## Cells covered by an area shape inside one side's zone.
##   CELL   the centre only
##   PLUS   centre + orthogonal neighbours
##   X      centre + diagonal neighbours
##   BLAST  3 x 3 around the centre
##   LANE   the whole lane of the centre (zone columns)
##   COLUMN the whole column of the centre
##   TWIN_LANES   every lane except `safe_lane` (stored in centre.y of the shape call)
##   TWIN_COLUMNS the centre column and the one in front of it
static func shape_cells(shape: String, center_col: int, center_lane: int, zone: Array) -> Array:
	var output: Array = []
	var add := func(col: int, lane: int) -> void:
		if lane < 0 or lane >= LANES or not zone.has(col): return
		var entry := [col, lane]
		if not output.has(entry): output.append(entry)
	match shape:
		"CELL":
			add.call(center_col, center_lane)
		"PLUS":
			add.call(center_col, center_lane)
			add.call(center_col - 1, center_lane)
			add.call(center_col + 1, center_lane)
			add.call(center_col, center_lane - 1)
			add.call(center_col, center_lane + 1)
		"X":
			add.call(center_col, center_lane)
			for dc in [-1, 1]:
				for dl in [-1, 1]:
					add.call(center_col + dc, center_lane + dl)
		"BLAST":
			for dc in [-1, 0, 1]:
				for dl in [-1, 0, 1]:
					add.call(center_col + dc, center_lane + dl)
		"LANE":
			for col in zone:
				add.call(int(col), center_lane)
		"COLUMN":
			for lane in range(LANES):
				add.call(center_col, lane)
		"TWIN_LANES":
			for lane in range(LANES):
				if lane == center_lane: continue
				for col in zone:
					add.call(int(col), lane)
		"TWIN_COLUMNS":
			var forward := 1 if zone.has(0) else -1
			for lane in range(LANES):
				add.call(center_col, lane)
				add.call(center_col + forward, lane)
	return output

## Every placement of `shape` in the zone, as {center, cells}. TWIN_LANES
## centres name the safe lane.
static func shape_candidates(shape: String, zone: Array) -> Array:
	var output: Array = []
	var seen: Dictionary = {}
	for col in zone:
		for lane in range(LANES):
			var cells := shape_cells(shape, int(col), lane, zone)
			if cells.is_empty(): continue
			var signature := JSON.stringify(cells)
			if seen.has(signature): continue
			seen[signature] = true
			output.append({"center": [int(col), lane], "cells": cells})
	return output

## The placement of `shape` hitting the most of `units` (ties: the most total
## threat, then the first candidate), so area attacks aim like a player would.
static func best_shape_placement(shape: String, zone: Array, units: Array) -> Dictionary:
	var best := {}
	var best_score := -1.0
	for candidate in shape_candidates(shape, zone):
		var score := 0.0
		for unit in units:
			if not UnitState.alive(unit): continue
			if has_cell(candidate.cells, int(unit.get("col", -9)), int(unit.get("lane", -9))):
				score += 1.0 + float(unit.get("threat", 1.0)) * .01
		if score > best_score:
			best_score = score
			best = candidate
	return best
