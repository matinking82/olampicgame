class_name GameState
extends RefCounted
## One run of Sudoku Pop. The view calls place() and use_power() and
## animates the event dictionaries they return.

const SEED_TILES := 8
const NO_CELL := Vector2i(-1, -1)

var board := Board.new()
## Piece or null per slot.
var tray: Array = [null, null, null]
var score := 0
var streak := 0
## Non-clearing turns in a row; the streak breaks when this hits STREAK_GRACE.
var misses := 0
var level := 1
var turns := 0
var game_over := false
var powers := Powers.new()
var generator: PieceGenerator
var rng := RandomNumberGenerator.new()
var next_reroll_at := Powers.REROLL_EVERY

# Run stats for the game-over screen.
var best_streak := 0
var best_cascade := 0
var total_pops := 0
var total_blasts := 0


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		seed_value = randi() + 1
	rng.seed = seed_value
	generator = PieceGenerator.new(seed_value * 7919 + 1)


func start() -> void:
	_seed_board()
	_deal()
	game_over = _is_dead_end()


func piece(slot: int) -> Piece:
	return tray[slot]


func rotate(slot: int) -> void:
	if tray[slot] != null:
		tray[slot] = piece(slot).rotated()


func can_place(slot: int, origin: Vector2i) -> bool:
	return not game_over and tray[slot] != null and Rules.can_place(board, piece(slot), origin)


## What a placement would do, without changing anything. Empty if it doesn't fit.
func preview(slot: int, origin: Vector2i) -> Dictionary:
	if not can_place(slot, origin):
		return {}
	var sim := board.copy()
	var cells := Rules.place(sim, piece(slot), origin)
	return {"cells": cells, "steps": Rules.resolve(sim, cells)}


## No tray piece fits anywhere, in any rotation.
func is_stuck() -> bool:
	for p in tray:
		if p != null and Rules.fits_any_rotation(board, p):
			return false
	return true


func place(slot: int, origin: Vector2i) -> Dictionary:
	if not can_place(slot, origin):
		return {}
	var p := piece(slot)
	tray[slot] = null
	var cells := Rules.place(board, p, origin)
	var steps := Rules.resolve(board, cells)

	var clear_points := 0
	var earned: Array[int] = []
	for step in steps:
		clear_points += Scoring.step_points(step)
		total_blasts += step.units.size()
		powers.pending_wilds += step.units.size()
		for pop: Dictionary in step.pops:
			total_pops += 1
			var kind := Powers.for_pop(pop.cells.size())
			if kind >= 0:
				earned.append(kind)

	var cleared := not steps.is_empty()
	if cleared:
		streak += 1
		misses = 0
	else:
		misses += 1
		if misses >= Scoring.STREAK_GRACE:
			streak = 0
			misses = 0
	best_streak = maxi(best_streak, streak)
	best_cascade = maxi(best_cascade, steps.size())
	var mult := Scoring.streak_mult(streak)
	var points := p.size() * Scoring.PLACE_POINTS + roundi(clear_points * mult)
	var perfect := cleared and board.count_tiles() == 0
	if perfect:
		points += Scoring.PERFECT_POINTS

	var result := {
		"cells": cells,
		"values": p.values,
		"steps": steps,
		"streak": streak,
		"multiplier": mult,
		"fever": Scoring.is_fever(streak),
		"perfect": perfect,
	}
	result.merge(_award(points, earned))
	turns += 1
	var old_level := level
	level = Difficulty.level_for(turns)
	result["level"] = level
	result["level_up"] = level > old_level
	result["stone"] = _maybe_drop_stone()
	result["dealt"] = tray.all(func(t: Variant) -> bool: return t == null)
	if result.dealt:
		_deal()
	game_over = _is_dead_end()
	result["game_over"] = game_over
	return result


## Uses the power in a slot. Laser, Bomb and Hammer aim at a cell; Nuke
## removes every tile with the digit at the target; Reroll needs no target.
func use_power(slot: int, target: Vector2i = NO_CELL) -> Dictionary:
	if game_over or slot < 0 or slot >= powers.slots.size():
		return {}
	var kind := powers.slots[slot]
	if Powers.needs_target(kind) and not Board.in_bounds(target):
		return {}
	var area: Array[Vector2i] = []
	match kind:
		Powers.Kind.LASER:
			area = Rules.cross(target)
		Powers.Kind.BOMB:
			area = Rules.area_3x3(target)
		Powers.Kind.NUKE:
			var v := board.get_cell(target)
			if not Board.is_digit(v):
				return {}
			area = Rules.cells_with_value(board, v)
		Powers.Kind.HAMMER:
			if board.is_empty(target):
				return {}
	powers.take(slot)

	var hits := Rules.clear_cells(board, [])
	if kind == Powers.Kind.REROLL:
		tray = [null, null, null]
		_deal()
	elif kind == Powers.Kind.HAMMER:
		# The hammer smashes anything, stones included.
		var v := board.get_cell(target)
		board.set_cell(target, Board.EMPTY)
		if Board.is_stone(v):
			hits.broken.append(target)
		else:
			hits.cleared.append(target)
	else:
		hits = Rules.clear_cells(board, area)

	var points: int = hits.cleared.size() * Scoring.POWER_CLEAR_POINTS
	var perfect: bool = not hits.cleared.is_empty() and board.count_tiles() == 0
	if perfect:
		points += Scoring.PERFECT_POINTS
	var result := {"kind": kind, "target": target, "area": area, "perfect": perfect}
	result.merge(hits)
	result.merge(_award(points, []))
	game_over = _is_dead_end()
	result["game_over"] = game_over
	return result


## Adds points, fills the meter and hands out powers. Powers that don't
## fit in a slot pay OVERFLOW_POINTS instead.
func _award(points: int, earned: Array[int]) -> Dictionary:
	var kinds := earned.duplicate()
	for i in powers.charge(points):
		kinds.append(Powers.Kind.HAMMER)
	score += points
	while score >= next_reroll_at:
		kinds.append(Powers.Kind.REROLL)
		next_reroll_at += Powers.REROLL_EVERY
	var added: Array[int] = []
	var overflow := 0
	for k in kinds:
		if powers.add(k):
			added.append(k)
		else:
			overflow += 1
	var bonus := overflow * Powers.OVERFLOW_POINTS
	score += bonus
	return {
		"points": points + bonus,
		"powers_earned": added,
		"overflow": overflow,
		"level": level,
		"level_up": false,
	}


func _deal() -> void:
	var pieces := generator.deal(board, level)
	for i in pieces.size():
		var p := pieces[i]
		if powers.pending_wilds > 0:
			p.values[rng.randi_range(0, p.size() - 1)] = Board.WILD
			powers.pending_wilds -= 1
		tray[i] = p


func _seed_board() -> void:
	var placed := 0
	var guard := 0
	while placed < SEED_TILES and guard < 1000:
		guard += 1
		var c := Vector2i(rng.randi_range(0, Board.SIZE - 1), rng.randi_range(0, Board.SIZE - 1))
		if not board.is_empty(c):
			continue
		board.set_cell(c, rng.randi_range(1, 9))
		if not Rules.find_groups(board).is_empty():
			board.set_cell(c, Board.EMPTY)
			continue
		placed += 1


func _maybe_drop_stone() -> Vector2i:
	var every := Difficulty.stone_every(level)
	if every <= 0 or turns % every != 0:
		return NO_CELL
	var empties := board.empty_cells()
	if empties.is_empty():
		return NO_CELL
	var c := empties[rng.randi_range(0, empties.size() - 1)]
	board.set_cell(c, Board.STONE)
	return c


## The run is over when nothing fits and no power is left to make room.
func _is_dead_end() -> bool:
	return powers.slots.is_empty() and is_stuck()
