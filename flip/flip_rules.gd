class_name FlipRules
extends RefCounted
## Flip Four's rules: Connect Four crossed with Reversi, on a w x h upright
## board stored as a flat array, index y * w + x with row 0 at the top. A
## cell is EMPTY, a side's disc (0 Sun, 1 Ice), a side's LOCKED disc
## (LOCKED + side) or a BLOCK (a fixed candy stone that discs stack on and
## that breaks lines).
##
## A move drops a disc down a column to the lowest free cell. Then, as in
## Reversi, every straight line (8 directions) of unlocked enemy discs
## trapped between the new disc and another of the mover's flips to the
## mover. Then any run of four or more of the mover's discs in a row
## (across, up, or diagonal) LOCKS: locked discs can never flip again, and
## an enemy's locked disc stops a flip line like a wall. When every column
## is full, the most discs wins.

const EMPTY := -1
const BLOCK := 2
## A locked disc is LOCKED + its side.
const LOCKED := 4
const LINE := 4
const DIRS := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]

static var _rays := {}
## Per board shape: every window of LINE cells in a row.
static var _windows := {}


static func rays(w: int, h: int) -> Array:
	var key := w * 100 + h
	if not _rays.has(key):
		var all := []
		for i in w * h:
			var per := []
			for d: Vector2i in DIRS:
				var ray := PackedInt32Array()
				var x := i % w + d.x
				var y := i / w + d.y
				while x >= 0 and y >= 0 and x < w and y < h:
					ray.append(y * w + x)
					x += d.x
					y += d.y
				if ray.size() >= 2:
					per.append(ray)
			all.append(per)
		_rays[key] = all
	return _rays[key]


static func windows(w: int, h: int) -> Array:
	var key := w * 100 + h
	if not _windows.has(key):
		var out := []
		for y in h:
			for x in w:
				for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
					var ex := x + d.x * (LINE - 1)
					var ey := y + d.y * (LINE - 1)
					if ex < 0 or ey < 0 or ex >= w or ey >= h:
						continue
					var win := PackedInt32Array()
					for k in LINE:
						win.append((y + d.y * k) * w + x + d.x * k)
					out.append(win)
		_windows[key] = out
	return _windows[key]


static func new_board(w: int, h: int, blocks: PackedInt32Array = PackedInt32Array()) -> PackedInt32Array:
	var b := PackedInt32Array()
	b.resize(w * h)
	b.fill(EMPTY)
	for i in blocks:
		b[i] = BLOCK
	return b


## The cell a disc dropped in `col` lands on, or -1 if the column is full.
static func landing(b: PackedInt32Array, w: int, h: int, col: int) -> int:
	if col < 0 or col >= w or b[col] != EMPTY:
		return -1
	var y := 0
	while y + 1 < h and b[(y + 1) * w + col] == EMPTY:
		y += 1
	return y * w + col


static func can_drop(b: PackedInt32Array, w: int, col: int) -> bool:
	return col >= 0 and col < w and b[col] == EMPTY


## Columns that still take a disc.
static func moves(b: PackedInt32Array, w: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for x in w:
		if b[x] == EMPTY:
			out.append(x)
	return out


static func is_full(b: PackedInt32Array, w: int) -> bool:
	for x in w:
		if b[x] == EMPTY:
			return false
	return true


## The discs a disc of `side` at cell `i` would flip.
static func flips(b: PackedInt32Array, w: int, h: int, i: int, side: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var other := 1 - side
	for ray: PackedInt32Array in rays(w, h)[i]:
		var k := 0
		while k < ray.size() and b[ray[k]] == other:
			k += 1
		if k > 0 and k < ray.size() and owner(b[ray[k]]) == side:
			for j in k:
				out.append(ray[j])
	return out


## The side a cell's disc belongs to (locked or not), or -1.
static func owner(v: int) -> int:
	if v == 0 or v == 1:
		return v
	if v == LOCKED or v == LOCKED + 1:
		return v - LOCKED
	return -1


static func is_locked(v: int) -> bool:
	return v >= LOCKED


## Drops a disc in place, flips and locks. Returns {"at": cell, "flipped":
## cells, "locked": newly locked cells, "runs": the runs that locked}, or an
## empty dictionary if the column is full.
static func drop(b: PackedInt32Array, w: int, h: int, col: int, side: int) -> Dictionary:
	var at := landing(b, w, h, col)
	if at < 0:
		return {}
	b[at] = side
	var flipped := flips(b, w, h, at, side)
	for c in flipped:
		b[c] = side
	var new_runs := []
	var locked := PackedInt32Array()
	for run: PackedInt32Array in runs(b, w, h, side):
		var fresh := false
		for c in run:
			if not is_locked(b[c]):
				fresh = true
				break
		if fresh:
			new_runs.append(run)
			for c in run:
				if not is_locked(b[c]) and not locked.has(c):
					locked.append(c)
	for c in locked:
		b[c] = LOCKED + side
	return {"at": at, "flipped": flipped, "locked": locked, "runs": new_runs}


## The runs of `side` as separate lines (start and end cells), for drawing.
static func runs(b: PackedInt32Array, w: int, h: int, side: int) -> Array:
	var out := []
	for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
		for y in h:
			for x in w:
				# Only start where the run starts.
				var px := x - d.x
				var py := y - d.y
				if px >= 0 and py >= 0 and px < w and py < h and owner(b[py * w + px]) == side:
					continue
				var len := 0
				var cx := x
				var cy := y
				while cx >= 0 and cy >= 0 and cx < w and cy < h and owner(b[cy * w + cx]) == side:
					len += 1
					cx += d.x
					cy += d.y
				if len >= LINE:
					var cells := PackedInt32Array()
					for k in len:
						cells.append((y + d.y * k) * w + x + d.x * k)
					out.append(cells)
	return out


## Discs of a side, locked or not (or EMPTY cells for side -1).
static func count(b: PackedInt32Array, side: int) -> int:
	var c := 0
	for v in b:
		if v == side or (side >= 0 and v == LOCKED + side):
			c += 1
	return c


static func count_locked(b: PackedInt32Array, side: int) -> int:
	var c := 0
	for v in b:
		if v == LOCKED + side:
			c += 1
	return c


## The side with more discs, or -1 for a tie.
static func leader(b: PackedInt32Array) -> int:
	var a := count(b, 0)
	var c := count(b, 1)
	return 0 if a > c else (1 if c > a else -1)


## Blocks in mirrored pairs, kept out of the top two rows so every column
## still holds a few discs.
static func make_blocks(w: int, h: int, pairs: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var spots: Array[Vector2i] = []
	for y in range(2, h):
		for x in w / 2:
			spots.append(Vector2i(x, y))
	var out := PackedInt32Array()
	for p in pairs:
		if spots.is_empty():
			break
		var s: Vector2i = spots.pop_at(rng.randi_range(0, spots.size() - 1))
		out.append(s.y * w + s.x)
		out.append(s.y * w + (w - 1 - s.x))
	return out


## A board from text rows (top first): "x" Sun, "o" Ice, "X" and "O"
## locked, "#" a block.
static func from_rows(rows: Array) -> PackedInt32Array:
	var h := rows.size()
	var w: int = String(rows[0]).length()
	var b := new_board(w, h)
	for y in h:
		var row: String = rows[y]
		for x in w:
			match row[x]:
				"x":
					b[y * w + x] = 0
				"o":
					b[y * w + x] = 1
				"X":
					b[y * w + x] = LOCKED
				"O":
					b[y * w + x] = LOCKED + 1
				"#":
					b[y * w + x] = BLOCK
	return b
