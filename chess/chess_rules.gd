class_name ChessRules
extends RefCounted
## Merge Mate's rules on a plain 8x8 array of ints, kept fast for the CPU
## search. A piece is `type | side << 3`; 0 is an empty square. Side 0 plays
## from the bottom (rows 6-7) upwards, side 1 from the top downwards.
##
## Chess moves and captures, plus merging: drag a piece onto a friendly twin
## of the same tier that it touches (any of the 8 neighbours) or could reach
## with a normal move, and they fuse one tier up:
##   pawn + pawn -> knight or bishop -> rook -> queen -> empress (queen + knight moves).
## No castling, no en passant, and pawns step one square. A pawn reaching the
## far row becomes a queen.

const SIZE := 8
const CELLS := 64
const EMPTY := 0
enum { PAWN = 1, KNIGHT, BISHOP, ROOK, QUEEN, EMPRESS, KING }
## Merge tier per type (index = type). Knight and bishop share a tier.
const TIER := [0, 1, 2, 2, 3, 4, 5, 0]
const MAX_TIER := 5
const NAMES := ["", "Pawn", "Knight", "Bishop", "Rook", "Queen", "Empress", "King"]

const KNIGHT_STEPS := [Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2),
	Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2)]
const KING_STEPS := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
const ORTHO := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIAG := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


static func piece(type: int, side: int) -> int:
	return type | (side << 3)


static func type_of(p: int) -> int:
	return p & 7


static func side_of(p: int) -> int:
	return p >> 3


static func idx(x: int, y: int) -> int:
	return y * SIZE + x


static func cell(i: int) -> Vector2i:
	return Vector2i(i % SIZE, i / SIZE)


static func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < SIZE and y < SIZE


## Row direction a side's pawns walk: up the screen for side 0.
static func forward(side: int) -> int:
	return -1 if side == 0 else 1


static func last_row(side: int) -> int:
	return 0 if side == 0 else SIZE - 1


## The two rows nearest a side's edge, where its new pieces appear.
static func home_rows(side: int) -> Array[int]:
	return [6, 7] if side == 0 else [0, 1]


## True when these two pieces fuse: same side, same tier, not kings, not maxed.
static func can_merge(a: int, b: int) -> bool:
	if a == EMPTY or b == EMPTY or side_of(a) != side_of(b):
		return false
	var t: int = TIER[type_of(a)]
	return t > 0 and t < MAX_TIER and t == TIER[type_of(b)]


## The type two merging pieces of `type` become. Pawns become a knight or a
## bishop at random; `roll` (0-1) picks which.
static func merged_type(type: int, roll: float = 0.0) -> int:
	match TIER[type]:
		1:
			return KNIGHT if roll < 0.5 else BISHOP
		2:
			return ROOK
		3:
			return QUEEN
		4:
			return EMPRESS
	return type


static func encode(from: int, to: int) -> int:
	return from | (to << 6)


static func move_from(m: int) -> int:
	return m & 63


static func move_to(m: int) -> int:
	return m >> 6


# --- Move generation -----------------------------------------------------------

## Every square the piece on `from` can move, capture or merge into, ignoring
## whether its own king would be left in check.
static func targets(cells: PackedInt32Array, from: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var p := cells[from]
	if p == EMPTY:
		return out
	var type := type_of(p)
	var side := side_of(p)
	var x := from % SIZE
	var y := from / SIZE
	match type:
		PAWN:
			var ny := y + forward(side)
			if ny >= 0 and ny < SIZE:
				if cells[idx(x, ny)] == EMPTY:
					out.append(idx(x, ny))
				for dx: int in [-1, 1]:
					if in_bounds(x + dx, ny):
						var q := cells[idx(x + dx, ny)]
						if q != EMPTY and side_of(q) != side:
							out.append(idx(x + dx, ny))
		KNIGHT:
			_steps(cells, p, x, y, KNIGHT_STEPS, out)
		BISHOP:
			_slides(cells, p, x, y, DIAG, out)
		ROOK:
			_slides(cells, p, x, y, ORTHO, out)
		QUEEN:
			_slides(cells, p, x, y, ORTHO, out)
			_slides(cells, p, x, y, DIAG, out)
		EMPRESS:
			_slides(cells, p, x, y, ORTHO, out)
			_slides(cells, p, x, y, DIAG, out)
			_steps(cells, p, x, y, KNIGHT_STEPS, out)
		KING:
			_steps(cells, p, x, y, KING_STEPS, out)
	# Any twin touching it can be merged into, whatever the piece's moves.
	if TIER[type] > 0 and TIER[type] < MAX_TIER:
		for d: Vector2i in KING_STEPS:
			if in_bounds(x + d.x, y + d.y):
				var t := idx(x + d.x, y + d.y)
				if can_merge(p, cells[t]) and not out.has(t):
					out.append(t)
	return out


static func _steps(cells: PackedInt32Array, p: int, x: int, y: int, steps: Array, out: PackedInt32Array) -> void:
	var side := side_of(p)
	for d: Vector2i in steps:
		var nx := x + d.x
		var ny := y + d.y
		if not in_bounds(nx, ny):
			continue
		var t := idx(nx, ny)
		var q := cells[t]
		if q == EMPTY or side_of(q) != side or can_merge(p, q):
			out.append(t)


static func _slides(cells: PackedInt32Array, p: int, x: int, y: int, dirs: Array, out: PackedInt32Array) -> void:
	var side := side_of(p)
	for d: Vector2i in dirs:
		var nx := x + d.x
		var ny := y + d.y
		while in_bounds(nx, ny):
			var t := idx(nx, ny)
			var q := cells[t]
			if q == EMPTY:
				out.append(t)
			else:
				if side_of(q) != side or can_merge(p, q):
					out.append(t)
				break
			nx += d.x
			ny += d.y


## All of a side's actions as encoded moves, ignoring king safety.
static func pseudo_moves(cells: PackedInt32Array, side: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for from in CELLS:
		var p := cells[from]
		if p != EMPTY and side_of(p) == side:
			for to in targets(cells, from):
				out.append(encode(from, to))
	return out


## Actions that don't leave the mover's own king in check.
static func legal_moves(cells: PackedInt32Array, side: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for m in pseudo_moves(cells, side):
		if is_legal(cells, move_from(m), move_to(m)):
			out.append(m)
	return out


static func legal_targets(cells: PackedInt32Array, from: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for to in targets(cells, from):
		if is_legal(cells, from, to):
			out.append(to)
	return out


static func is_legal(cells: PackedInt32Array, from: int, to: int) -> bool:
	var side := side_of(cells[from])
	var next := apply(cells, from, to)
	return not in_check(next, side)


static func has_legal_move(cells: PackedInt32Array, side: int) -> bool:
	for from in CELLS:
		var p := cells[from]
		if p != EMPTY and side_of(p) == side:
			for to in targets(cells, from):
				if is_legal(cells, from, to):
					return true
	return false


## The board after an action. A merge leaves `merge_type` (or the knight for
## pawns, when not given) on the target square; a pawn on the far row
## becomes a queen.
static func apply(cells: PackedInt32Array, from: int, to: int, merge_type: int = 0) -> PackedInt32Array:
	var next := cells.duplicate()
	var p := next[from]
	var q := next[to]
	var side := side_of(p)
	next[from] = EMPTY
	if can_merge(p, q):
		next[to] = piece(merge_type if merge_type != 0 else merged_type(type_of(p)), side)
	elif type_of(p) == PAWN and to / SIZE == last_row(side):
		next[to] = piece(QUEEN, side)
	else:
		next[to] = p
	return next


# --- Attacks and check ---------------------------------------------------------

static func king_square(cells: PackedInt32Array, side: int) -> int:
	var king := piece(KING, side)
	for i in CELLS:
		if cells[i] == king:
			return i
	return -1


static func in_check(cells: PackedInt32Array, side: int) -> bool:
	var k := king_square(cells, side)
	return k >= 0 and is_attacked(cells, k, 1 - side)


## True when a piece of side `by` could capture on square `sq`.
static func is_attacked(cells: PackedInt32Array, sq: int, by: int) -> bool:
	var x := sq % SIZE
	var y := sq / SIZE
	# Pawns attack diagonally forward, so look one row back from their view.
	var py := y - forward(by)
	for dx: int in [-1, 1]:
		if in_bounds(x + dx, py) and cells[idx(x + dx, py)] == piece(PAWN, by):
			return true
	for d: Vector2i in KNIGHT_STEPS:
		if in_bounds(x + d.x, y + d.y):
			var q := cells[idx(x + d.x, y + d.y)]
			if q != EMPTY and side_of(q) == by and (type_of(q) == KNIGHT or type_of(q) == EMPRESS):
				return true
	for d: Vector2i in KING_STEPS:
		if in_bounds(x + d.x, y + d.y) and cells[idx(x + d.x, y + d.y)] == piece(KING, by):
			return true
	if _ray_hits(cells, x, y, ORTHO, by, ROOK):
		return true
	return _ray_hits(cells, x, y, DIAG, by, BISHOP)


## Whether the first piece along any of these rays is `by`'s `slider`, queen or empress.
static func _ray_hits(cells: PackedInt32Array, x: int, y: int, dirs: Array, by: int, slider: int) -> bool:
	for d: Vector2i in dirs:
		var nx := x + d.x
		var ny := y + d.y
		while in_bounds(nx, ny):
			var q := cells[idx(nx, ny)]
			if q != EMPTY:
				if side_of(q) == by:
					var t := type_of(q)
					if t == slider or t == QUEEN or t == EMPRESS:
						return true
				break
			nx += d.x
			ny += d.y
	return false


## Builds a board from 8 strings, top row first. Uppercase is side 0,
## lowercase side 1: P N B R Q E K; '.' or anything else is empty.
static func from_rows(rows: Array) -> PackedInt32Array:
	var cells := PackedInt32Array()
	cells.resize(CELLS)
	var letters := ".pnbrqek"
	for y in mini(rows.size(), SIZE):
		var row: String = rows[y]
		for x in mini(row.length(), SIZE):
			var ch := row[x]
			var t := letters.find(ch.to_lower())
			if t > 0:
				cells[idx(x, y)] = piece(t, 0 if ch == ch.to_upper() else 1)
	return cells


static func to_rows(cells: PackedInt32Array) -> Array[String]:
	var letters := ".pnbrqek"
	var rows: Array[String] = []
	for y in SIZE:
		var row := ""
		for x in SIZE:
			var p := cells[idx(x, y)]
			var ch := letters[type_of(p)]
			row += ch.to_upper() if p != EMPTY and side_of(p) == 0 else ch
		rows.append(row)
	return rows
