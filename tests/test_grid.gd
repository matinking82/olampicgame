extends "res://tests/test_case.gd"
## Code Grid: Latin squares, feedback, the solver behind "codes left",
## checks, cracking, failing, levels and powers.

const R := preload("res://grid/grid_rules.gd")
const CODE := [1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1]
const SWAPPED := [2, 1, 3, 4, 3, 4, 1, 2, 1, 2, 4, 3, 4, 3, 2, 1]


func _match() -> GridMatch:
	var m := GridMatch.new(7)
	m.start()
	m.set_code(PackedInt32Array(CODE), {})
	return m


func _fill(m: GridMatch, values: Array) -> void:
	for i in values.size():
		m.place(i, values[i])


func test_random_squares_are_latin() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	for n in [4, 5, 6]:
		var sq := R.random_square(n, rng)
		check_eq(sq.size(), n * n, "a full square")
		check(R.conflicts(sq, n).is_empty(), "no repeats in rows or columns (%d)" % n)


func test_feedback_counts_rows_and_columns() -> void:
	var fb := R.feedback(PackedInt32Array(CODE), PackedInt32Array(SWAPPED), 4)
	check_eq(Array(fb.rows), [2, 4, 2, 4], "rows")
	check_eq(Array(fb.cols), [2, 2, 4, 4], "columns")


func test_solver_counts_codes_that_fit() -> void:
	check_eq(R.solve(4, {}, [], 1000).count, 576, "there are 576 Latin squares of 4")
	var fb := R.feedback(PackedInt32Array(CODE), PackedInt32Array(SWAPPED), 4)
	var clue := {"guess": PackedInt32Array(SWAPPED), "rows": fb.rows, "cols": fb.cols}
	var found := R.solve(4, {}, [clue], 1000)
	check(found.count >= 1, "the code fits its own clue")
	check(found.complete, "the count finished")
	var rng := RandomNumberGenerator.new()
	for k in 5:
		var any: PackedInt32Array = R.solve(4, {}, [clue], 1, rng).first
		var again := R.feedback(any, PackedInt32Array(SWAPPED), 4)
		check(again.rows == fb.rows and again.cols == fb.cols, "every fit gives the same counts")
	check(not R.solve(6, {}, [], 99999, null, 100).complete, "a small budget gives up")


func test_checks_need_a_full_valid_grid() -> void:
	var m := _match()
	check_eq(m.check_blocker(), "Fill every square first", "empty")
	_fill(m, SWAPPED)
	m.place(0, 1)
	check_eq(m.check_blocker(), "A row or column repeats a digit", "a repeat")
	m.place(0, 2)
	check_eq(m.check_blocker(), "", "ready")


func test_a_check_scores_and_records_its_counts() -> void:
	var m := _match()
	_fill(m, SWAPPED)
	var result := m.check()
	check_eq(result.hits, 12, "12 squares right")
	check_eq(result.points, GridMatch.HIT_POINTS * 12, "points for the hits")
	check_eq(m.checks_left(), m.max_checks - 1, "a check used")
	check(m.is_running(), "not cracked yet")


func test_cracking_pays_and_climbs() -> void:
	var m := _match()
	_fill(m, CODE)
	var result := m.check()
	check(result.solved, "cracked")
	check(result.perfect, "in one check, under par")
	check_eq(m.stars(), 3, "three stars")
	check(result.crack_points >= GridMatch.CRACK_POINTS * 16, "the crack bonus")
	m.next_level()
	check_eq(m.level, 2, "level 2")
	check_eq(m.streak, 1, "a streak of one")


func test_running_out_of_checks_costs_a_heart() -> void:
	var m := _match()
	_fill(m, SWAPPED)
	var result := {}
	for k in m.max_checks:
		result = m.check()
	check(result.failed, "out of checks")
	check_eq(m.hearts, GridMatch.HEARTS - 1, "a heart lost")
	check_eq(m.streak, 0, "the streak ends")
	m.next_level()
	check_eq(m.level, 1, "the same level again")


func test_givens_are_fixed_and_spread() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var code := R.random_square(5, rng)
	var shown := R.make_givens(code, 5, 6, rng)
	check_eq(shown.size(), 6, "six givens")
	var per_row := [0, 0, 0, 0, 0]
	for i: int in shown:
		check_eq(shown[i], code[i], "givens show the code")
		per_row[i / 5] += 1
	check(per_row.max() <= 2, "no row gets them all")
	var m := _match()
	m.set_code(code, shown)
	check(not m.place(shown.keys()[0], 1), "a given can't change")


func test_powers_reveal_and_test() -> void:
	var m := _match()
	_fill(m, SWAPPED)
	m.charges = 2
	var i := m.reveal()
	check([0, 1, 8, 9].has(i), "REVEAL picks a wrong square")
	check_eq(m.grid[i], CODE[i], "and puts the right digit there")
	var j := 9 if i != 9 else 8
	check_eq(m.test(j), 0, "TEST says a wrong square is wrong")
	check(m.ruled_out[j].has(SWAPPED[j]), "and rules that digit out there")
	check_eq(m.charges, 0, "both spent a charge")


func test_levels_grow() -> void:
	check_eq(GridMatch.setup(1).n, 4, "4x4 first")
	check_eq(GridMatch.setup(5).n, 5, "then 5x5")
	check_eq(GridMatch.setup(20).n, 6, "6x6 at the top")
	check(GridMatch.setup(3).givens < GridMatch.setup(1).givens, "fewer givens as you climb")
