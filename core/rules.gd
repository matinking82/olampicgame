class_name Rules
extends RefCounted
## Turn resolution: pops and merges, Sudoku blasts, golden stars and stones.
## Every function is static and only changes the board it is given.

const MIN_POP := 3
## Merge result for a group of 9s: an explosion instead of a new tile.
const STAR := -1
const MAX_STEPS := 64


static func can_place(board: Board, piece: Piece, origin: Vector2i) -> bool:
	for c in piece.cells_at(origin):
		if not Board.in_bounds(c) or not board.is_empty(c):
			return false
	return true


static func fits(board: Board, piece: Piece) -> bool:
	for y in Board.SIZE:
		for x in Board.SIZE:
			if can_place(board, piece, Vector2i(x, y)):
				return true
	return false


static func fits_any_rotation(board: Board, piece: Piece) -> bool:
	var p := piece
	for i in 4:
		if fits(board, p):
			return true
		p = p.rotated()
	return false


## Writes the piece onto the board and returns the cells it covered.
static func place(board: Board, piece: Piece, origin: Vector2i) -> Array[Vector2i]:
	var cells := piece.cells_at(origin)
	for i in cells.size():
		board.set_cell(cells[i], piece.values[i])
	return cells


## Resolves everything a placement sets off, step by step, until the board
## is calm. Each step blasts solved units and pops groups found on the same
## snapshot, then drops merged tiles, which can start the next step.
## `recent` are the cells just placed; merged tiles appear there when they can.
static func resolve(board: Board, recent: Array[Vector2i]) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	var hint := recent
	for depth in MAX_STEPS:
		var solved := board.units_in_state(Board.UnitState.SOLVED)
		var groups := find_groups(board)
		if solved.is_empty() and groups.is_empty():
			break
		var clear := {}
		for u in solved:
			for c: Vector2i in Board.units()[u]:
				clear[c] = true
		var pops: Array[Dictionary] = []
		for g in groups:
			var anchor := _pick_anchor(g.cells, hint)
			for c: Vector2i in g.cells:
				clear[c] = true
			var result: int = STAR if g.digit == 9 else g.digit + 1
			if result == STAR:
				for c in area_3x3(anchor):
					clear[c] = true
			pops.append({"digit": g.digit, "cells": g.cells, "anchor": anchor, "result": result})
		var hits := clear_cells(board, clear.keys())
		var next_hint: Array[Vector2i] = []
		for p in pops:
			if p.result != STAR:
				board.set_cell(p.anchor, p.result)
				next_hint.append(p.anchor)
		steps.append({
			"depth": depth,
			"units": solved,
			"pops": pops,
			"cleared": hits.cleared,
			"cracked": hits.cracked,
			"broken": hits.broken,
		})
		hint = next_hint
	return steps


## Connected groups of 3+ equal digits. Wilds join any group they touch.
## Groups never share a cell; bigger groups win when a wild is contested.
static func find_groups(board: Board) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for d in range(1, 10):
		var seen := {}
		for i in board.cells.size():
			if board.cells[i] != d:
				continue
			var start := Board.cell_at_index(i)
			if seen.has(start):
				continue
			var comp := _flood(board, start, d, true)
			for c in comp:
				if board.get_cell(c) == d:
					seen[c] = true
			if comp.size() >= MIN_POP:
				candidates.append({"digit": d, "cells": comp})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.cells.size() != b.cells.size():
			return a.cells.size() > b.cells.size()
		return a.digit > b.digit)
	var used := {}
	var groups: Array[Dictionary] = []
	for g in candidates:
		var clash := false
		for c: Vector2i in g.cells:
			if used.has(c):
				clash = true
				break
		if clash:
			continue
		for c: Vector2i in g.cells:
			used[c] = true
		groups.append(g)
	return groups


## Empties the given cells. Stones inside the area, or next to a tile that
## was cleared, crack once (a cracked stone breaks).
static func clear_cells(board: Board, area: Array) -> Dictionary:
	var cleared: Array[Vector2i] = []
	for c: Vector2i in area:
		if Board.is_tile(board.get_cell(c)):
			board.set_cell(c, Board.EMPTY)
			cleared.append(c)
	var hit := {}
	for c: Vector2i in area:
		if Board.is_stone(board.get_cell(c)):
			hit[c] = true
	for c in cleared:
		for n in Board.neighbors(c):
			if Board.is_stone(board.get_cell(n)):
				hit[n] = true
	var cracked: Array[Vector2i] = []
	var broken: Array[Vector2i] = []
	for c: Vector2i in hit:
		if board.get_cell(c) == Board.STONE:
			board.set_cell(c, Board.STONE_CRACKED)
			cracked.append(c)
		else:
			board.set_cell(c, Board.EMPTY)
			broken.append(c)
	return {"cleared": cleared, "cracked": cracked, "broken": broken}


static func area_3x3(center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := center + Vector2i(dx, dy)
			if Board.in_bounds(c):
				out.append(c)
	return out


## The whole row and column through a cell.
static func cross(center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in Board.SIZE:
		out.append(Vector2i(i, center.y))
		if i != center.y:
			out.append(Vector2i(center.x, i))
	return out


static func cells_with_value(board: Board, v: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in board.cells.size():
		if board.cells[i] == v:
			out.append(Board.cell_at_index(i))
	return out


## For each digit, how many empty cells would pop a group if that digit
## were dropped there. Index 0 is unused.
static func pop_opportunities(board: Board) -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(10)
	var empties := board.empty_cells()
	for d in range(1, 10):
		var comp_of := {}
		var sizes: Array[int] = []
		for i in board.cells.size():
			var start := Board.cell_at_index(i)
			if board.cells[i] != d or comp_of.has(start):
				continue
			var comp := _flood(board, start, d, false)
			for c in comp:
				comp_of[c] = sizes.size()
			sizes.append(comp.size())
		if sizes.is_empty():
			continue
		for e in empties:
			var touched := {}
			var total := 1
			for n in Board.neighbors(e):
				if comp_of.has(n) and not touched.has(comp_of[n]):
					touched[comp_of[n]] = true
					total += sizes[comp_of[n]]
			if total >= MIN_POP:
				counts[d] += 1
	return counts


## For each digit, how many nearly finished units (3 or fewer gaps, no
## repeats, no stones) are still missing it. Index 0 is unused.
static func sudoku_needs(board: Board) -> PackedInt32Array:
	var needs := PackedInt32Array()
	needs.resize(10)
	for unit: Array in Board.units():
		var present := {}
		var gaps := 0
		var usable := true
		for c: Vector2i in unit:
			var v := board.get_cell(c)
			if v == Board.EMPTY:
				gaps += 1
			elif Board.is_stone(v) or present.has(v):
				usable = false
				break
			elif Board.is_digit(v):
				present[v] = true
		if not usable or gaps == 0 or gaps > 3:
			continue
		for d in range(1, 10):
			if not present.has(d):
				needs[d] += 1
	return needs


## Sudoku pencil marks for the player: for every clean unit (no repeats,
## no stones) with at most `max_gaps` empty cells, its gaps get the digits
## the unit is still missing. A cell in two such units keeps only the
## digits both need. Returns cell -> Array[int], omitting cells with none.
static func pencil_marks(board: Board, max_gaps: int = 2) -> Dictionary:
	var marks := {}
	for unit: Array in Board.units():
		var present := {}
		var gaps: Array[Vector2i] = []
		var clean := true
		for c: Vector2i in unit:
			var v := board.get_cell(c)
			if v == Board.EMPTY:
				gaps.append(c)
			elif Board.is_stone(v) or present.has(v):
				clean = false
				break
			elif Board.is_digit(v):
				present[v] = true
		if not clean or gaps.is_empty() or gaps.size() > max_gaps:
			continue
		var missing: Array[int] = []
		for d in range(1, 10):
			if not present.has(d):
				missing.append(d)
		for c in gaps:
			if marks.has(c):
				var both: Array[int] = []
				for d: int in marks[c]:
					if missing.has(d):
						both.append(d)
				marks[c] = both
			else:
				marks[c] = missing.duplicate()
	for c: Vector2i in marks.keys():
		if marks[c].is_empty():
			marks.erase(c)
	return marks


static func _flood(board: Board, start: Vector2i, digit: int, with_wilds: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = [start]
	var seen := {start: true}
	var i := 0
	while i < out.size():
		for n in Board.neighbors(out[i]):
			if seen.has(n):
				continue
			var v := board.get_cell(n)
			if v == digit or (with_wilds and v == Board.WILD):
				seen[n] = true
				out.append(n)
		i += 1
	return out


static func _pick_anchor(cells: Array, hint: Array[Vector2i]) -> Vector2i:
	for h in hint:
		if cells.has(h):
			return h
	var center := Vector2.ZERO
	for c: Vector2i in cells:
		center += Vector2(c)
	center /= cells.size()
	var best: Vector2i = cells[0]
	var best_dist := INF
	for c: Vector2i in cells:
		var dist := center.distance_squared_to(Vector2(c))
		if dist < best_dist - 0.0001:
			best = c
			best_dist = dist
	return best
