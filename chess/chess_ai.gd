class_name ChessAI
extends RefCounted
## The CPU opponent: a small alpha-beta search over ChessRules boards.
## Spawns are ignored while searching (they're random), and merges of two
## pawns are assumed to give a knight. `noise` adds up to that many points
## of random slack to each root move, which makes the early rounds fumble.

const R := preload("res://chess/chess_rules.gd")
## Piece values for the search. Each tier is worth a bit more than the two
## pieces that make it, so merging looks good but never wins by itself.
const VALUE := [0, 100, 280, 290, 600, 1250, 2700, 0]
const MATE := 100000
const INF := 1000000


## Picks an action for `side`, or -1 if it has none. Mate in one is always taken.
static func choose(cells: PackedInt32Array, side: int, depth: int = 2, noise: float = 0.0,
		rng: RandomNumberGenerator = null) -> int:
	var moves := _ordered(cells, R.legal_moves(cells, side))
	if moves.is_empty():
		return -1
	var best_move := moves[0]
	var best := -INF
	var best_jittered := -INF
	for m in moves:
		var next := R.apply(cells, R.move_from(m), R.move_to(m))
		if R.in_check(next, 1 - side) and not R.has_legal_move(next, 1 - side):
			return m
		# Moves that can't come within `noise` of the best are cut short.
		var floor_score := best - int(noise) - 1
		var s := -_search(next, 1 - side, depth - 1, -INF, -floor_score, 1)
		var jittered := s + (rng.randf() * noise if rng != null and noise > 0.0 else 0.0)
		best = maxi(best, s)
		if jittered > best_jittered:
			best_jittered = jittered
			best_move = m
	return best_move


static func _search(cells: PackedInt32Array, side: int, depth: int, alpha: int, beta: int, ply: int) -> int:
	if depth <= 0:
		return evaluate(cells, side)
	var best := -INF
	var any := false
	for m in _ordered(cells, R.pseudo_moves(cells, side)):
		var next := R.apply(cells, R.move_from(m), R.move_to(m))
		if R.in_check(next, side):
			continue
		any = true
		var s := -_search(next, 1 - side, depth - 1, -beta, -alpha, ply + 1)
		if s > best:
			best = s
			if s > alpha:
				alpha = s
				if alpha >= beta:
					break
	if not any:
		return -MATE + ply if R.in_check(cells, side) else 0
	return best


## Captures first (biggest victim first), then merges, then the rest.
static func _ordered(cells: PackedInt32Array, moves: PackedInt32Array) -> PackedInt32Array:
	var keyed: Array[Vector2i] = []
	for m in moves:
		var p := cells[R.move_from(m)]
		var q := cells[R.move_to(m)]
		var key := 0
		if q != R.EMPTY:
			if R.side_of(q) != R.side_of(p):
				key = 10000 + VALUE[R.type_of(q)] * 10 - VALUE[R.type_of(p)] / 10
			else:
				key = 5000 + VALUE[R.type_of(q)]
		keyed.append(Vector2i(key, m))
	keyed.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x > b.x)
	var out := PackedInt32Array()
	for k in keyed:
		out.append(k.y)
	return out


## Score of the position for `side`, the side to move.
static func evaluate(cells: PackedInt32Array, side: int) -> int:
	var score := 0
	for i in R.CELLS:
		var p := cells[i]
		if p == R.EMPTY:
			continue
		var type := R.type_of(p)
		var own := R.side_of(p)
		var x := i % R.SIZE
		var y := i / R.SIZE
		var v: int = VALUE[type]
		var advance := 7 - y if own == 0 else y
		match type:
			R.PAWN:
				v += advance * advance * 3
			R.KING:
				# Stay home behind the pawns.
				v -= maxi(0, advance - 1) * 25
			_:
				var center := 7 - absi(2 * x - 7) + 7 - absi(2 * y - 7)
				v += center * 3 + mini(advance, 5) * 4
		# Twins next to each other are a merge waiting to happen.
		if R.TIER[type] > 0 and R.TIER[type] < R.MAX_TIER:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
				if R.in_bounds(x + d.x, y + d.y) and R.can_merge(p, cells[R.idx(x + d.x, y + d.y)]):
					v += 12
		score += v if own == side else -v
	if R.in_check(cells, side):
		if not R.has_legal_move(cells, side):
			return -MATE
		score -= 40
	return score + _threat(cells, side)


## A cheap look one move further: the best capture the side to move has,
## counting a defended victim as a trade.
static func _threat(cells: PackedInt32Array, side: int) -> int:
	var best := 0
	for from in R.CELLS:
		var p := cells[from]
		if p == R.EMPTY or R.side_of(p) != side:
			continue
		for to in R.targets(cells, from):
			var q := cells[to]
			if q == R.EMPTY or R.side_of(q) == side:
				continue
			var gain: int = VALUE[R.type_of(q)]
			if R.is_attacked(cells, to, 1 - side):
				gain -= VALUE[R.type_of(p)]
			best = maxi(best, gain)
	return best * 4 / 5
