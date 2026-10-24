class_name FlipAI
extends RefCounted
## Flip Four's CPU: negamax with alpha-beta pruning over the columns.
## A position is judged by discs (locked ones count several times, since
## they're safe for good) and by open windows of four that could still
## lock. With few empty cells left it searches to the end and plays the
## disc count perfectly.

const R := preload("res://flip/flip_rules.gd")
const WIN := 100000
const DISC := 2
const LOCKED := 9
## What an open window with 1, 2 or 3 of a side's discs is worth.
const WINDOW := [0, 0, 2, 7]


## The column to play, or -1 when the board is full. `noise` adds that
## many points of randomness to each first move's value; from `endgame`
## empty cells it searches to the end.
static func choose(b: PackedInt32Array, w: int, h: int, side: int, depth: int, noise: float, endgame: int,
		rng: RandomNumberGenerator) -> int:
	var cols := _ordered(b, w)
	if cols.is_empty():
		return -1
	var empty := _open_cells(b, w, h)
	var exact := empty <= endgame
	var d := empty if exact else depth
	var best := -1
	var best_v := -INF
	var alpha := -float(WIN) * 10.0
	for col in cols:
		var c := b.duplicate()
		R.drop(c, w, h, col, side)
		var v := -_negamax(c, w, h, 1 - side, d - 1, -float(WIN) * 10.0, -alpha, exact)
		if noise > 0.0:
			v += rng.randf_range(-noise, noise)
		if v > best_v:
			best_v = v
			best = col
		if noise <= 0.0:
			alpha = maxf(alpha, v)
	return best


## The value of a position for `side` to move, searching `depth` deep.
static func _negamax(b: PackedInt32Array, w: int, h: int, side: int, depth: int, alpha: float, beta: float,
		exact: bool) -> float:
	var cols := _ordered(b, w)
	if cols.is_empty():
		return _final(b, side)
	if depth <= 0:
		return _final(b, side) if exact else evaluate(b, w, h, side)
	for col in cols:
		var c := b.duplicate()
		R.drop(c, w, h, col, side)
		var v := -_negamax(c, w, h, 1 - side, depth - 1, -beta, -alpha, exact)
		if v > alpha:
			alpha = v
			if alpha >= beta:
				break
	return alpha


## A full (or exactly searched) board: the disc margin, scaled so any win
## beats any heuristic value.
static func _final(b: PackedInt32Array, side: int) -> float:
	var margin := R.count(b, side) - R.count(b, 1 - side)
	return 0.0 if margin == 0 else float(WIN + absi(margin) * 100) * signf(margin)


## How good the board is for `side`, in rough points.
static func evaluate(b: PackedInt32Array, w: int, h: int, side: int) -> float:
	var other := 1 - side
	var score := 0
	for v in b:
		if v == side:
			score += DISC
		elif v == other:
			score -= DISC
		elif v == R.LOCKED + side:
			score += LOCKED
		elif v == R.LOCKED + other:
			score -= LOCKED
	for win: PackedInt32Array in R.windows(w, h):
		var mine := 0
		var theirs := 0
		var fresh := false
		var dead := false
		for c in win:
			var v := b[c]
			var o := R.owner(v)
			if o == side:
				mine += 1
			elif o == other:
				theirs += 1
			elif v == R.BLOCK:
				dead = true
			if v == 0 or v == 1 or v == R.EMPTY:
				fresh = true
		if dead or not fresh or (mine > 0 and theirs > 0):
			continue
		score += WINDOW[mini(mine, 3)] if theirs == 0 else -WINDOW[mini(theirs, 3)]
	return float(score)


## Empty cells a disc can still reach (cells under a block never fill).
static func _open_cells(b: PackedInt32Array, w: int, h: int) -> int:
	var c := 0
	for x in w:
		var y := 0
		while y < h and b[y * w + x] == R.EMPTY:
			c += 1
			y += 1
	return c


## Columns nearer the middle are tried first; they're usually better.
static func _ordered(b: PackedInt32Array, w: int) -> PackedInt32Array:
	var cols := R.moves(b, w)
	var mid := (w - 1) * 0.5
	var list := Array(cols)
	list.sort_custom(func(a: int, c: int) -> bool: return absf(a - mid) < absf(c - mid))
	return PackedInt32Array(list)
