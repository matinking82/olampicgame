class_name GridRules
extends RefCounted
## Code Grid's rules: Mastermind crossed with Sudoku. The secret code is an
## n x n Latin square of candy digits 1..n (every row and every column uses
## each digit once), stored flat, index y * n + x. A guess must be a whole
## grid that keeps the same rule; checking it tells you, for every row and
## every column, how many squares are exactly right, but not which.
##
## The solver counts the codes still possible given the clues (the givens
## and every check so far), which drives the "codes left" counter, the
## tests and the balance sim.

const EMPTY := 0


## A random Latin square, built square by square with shuffled digits.
static func random_square(n: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var found := solve(n, {}, [], 1, rng)
	return found.first


## Squares that clash with another of the same digit in their row or column.
static func conflicts(grid: PackedInt32Array, n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in grid.size():
		var v := grid[i]
		if v == EMPTY:
			continue
		var x := i % n
		var y := i / n
		for k in n:
			if (k != x and grid[y * n + k] == v) or (k != y and grid[k * n + x] == v):
				out.append(i)
				break
	return out


static func is_full(grid: PackedInt32Array) -> bool:
	for v in grid:
		if v == EMPTY:
			return false
	return true


## How many squares are exactly right in each row and each column.
static func feedback(code: PackedInt32Array, guess: PackedInt32Array, n: int) -> Dictionary:
	var rows := PackedInt32Array()
	var cols := PackedInt32Array()
	rows.resize(n)
	cols.resize(n)
	for i in code.size():
		if code[i] == guess[i]:
			rows[i / n] += 1
			cols[i % n] += 1
	return {"rows": rows, "cols": cols}


## Givens: squares of the code shown from the start, spread over the rows.
static func make_givens(code: PackedInt32Array, n: int, count: int, rng: RandomNumberGenerator) -> Dictionary:
	var order := range(code.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
	var out := {}
	# Round-robin over the rows, so no row is handed over whole.
	var per_row := []
	per_row.resize(n)
	per_row.fill(0)
	var limit := ceili(float(count) / n)
	for i: int in order:
		if out.size() >= count:
			break
		if per_row[i / n] < limit:
			out[i] = code[i]
			per_row[i / n] += 1
	return out


## Counts the codes (up to `cap`) that fit the givens (square -> digit) and
## every check ({"guess", "rows", "cols"}), and returns the first found.
## With `rng` the digits are tried in a random order, so the first is a
## random fit. The search gives up after `budget` steps (0 for no limit);
## then "complete" is false and the count is only a lower bound.
static func solve(n: int, givens: Dictionary, checks: Array, cap: int,
		rng: RandomNumberGenerator = null, budget: int = 0) -> Dictionary:
	var s := _Search.new()
	s.n = n
	s.cap = cap
	s.rng = rng
	s.budget = budget
	s.grid.resize(n * n)
	s.row_used.resize(n)
	s.col_used.resize(n)
	s.given.resize(n * n)
	for i: int in givens:
		s.given[i] = givens[i]
	for c: Dictionary in checks:
		s.guesses.append(c.guess)
		s.want_rows.append(c.rows)
		s.want_cols.append(c.cols)
		var rm := PackedInt32Array()
		rm.resize(n)
		s.row_hits.append(rm)
		var cm := PackedInt32Array()
		cm.resize(n)
		s.col_hits.append(cm)
	s.run(0)
	return {"count": s.count, "first": s.first, "complete": not s.gave_up}


## A depth-first fill, square by square, pruning as soon as a row or column
## can no longer match a check's counts.
class _Search:
	var n := 4
	var cap := 1
	var rng: RandomNumberGenerator
	var grid := PackedInt32Array()
	var given := PackedInt32Array()
	var row_used := PackedInt32Array()
	var col_used := PackedInt32Array()
	var guesses: Array[PackedInt32Array] = []
	var want_rows: Array[PackedInt32Array] = []
	var want_cols: Array[PackedInt32Array] = []
	var row_hits: Array[PackedInt32Array] = []
	var col_hits: Array[PackedInt32Array] = []
	var count := 0
	var first := PackedInt32Array()
	var budget := 0
	var steps := 0
	var gave_up := false

	func run(i: int) -> void:
		if count >= cap or gave_up:
			return
		steps += 1
		if budget > 0 and steps > budget:
			gave_up = true
			return
		if i == n * n:
			count += 1
			if first.is_empty():
				first = grid.duplicate()
			return
		var x := i % n
		var y := i / n
		var digits: Array = range(1, n + 1)
		if given[i] != 0:
			digits = [given[i]]
		elif rng != null:
			digits.shuffle()
		var row_left := n - 1 - x
		var col_left := n - 1 - y
		for v: int in digits:
			var bit := 1 << v
			if row_used[y] & bit or col_used[x] & bit:
				continue
			var ok := true
			var k := 0
			while k < guesses.size():
				var hit := 1 if guesses[k][i] == v else 0
				var rh := row_hits[k][y] + hit
				var ch := col_hits[k][x] + hit
				var wr := want_rows[k][y]
				if rh > wr or rh + row_left < wr:
					ok = false
					break
				# A check without column counts (an empty list) only limits rows.
				if not want_cols[k].is_empty():
					var wc := want_cols[k][x]
					if ch > wc or ch + col_left < wc:
						ok = false
						break
				k += 1
			if not ok:
				continue
			for j in guesses.size():
				if guesses[j][i] == v:
					row_hits[j][y] += 1
					col_hits[j][x] += 1
			grid[i] = v
			row_used[y] |= bit
			col_used[x] |= bit
			run(i + 1)
			row_used[y] &= ~bit
			col_used[x] &= ~bit
			grid[i] = 0
			for j in guesses.size():
				if guesses[j][i] == v:
					row_hits[j][y] -= 1
					col_hits[j][x] -= 1
			if count >= cap or gave_up:
				return
