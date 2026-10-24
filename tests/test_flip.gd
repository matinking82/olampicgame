extends "res://tests/test_case.gd"
## Flip Four: drops, flips in every direction, locking lines, full racks,
## rounds, hearts, powers and the CPU.

const R := preload("res://flip/flip_rules.gd")


func _match(rows: Array, against_cpu: bool = true) -> FlipMatch:
	var m := FlipMatch.new(5, against_cpu)
	m.start()
	m.set_board(R.from_rows(rows), String(rows[0]).length())
	m.turn = 0
	return m


func test_discs_fall_to_the_lowest_free_hole() -> void:
	var b := R.from_rows(["...", "...", "x.#"])
	check_eq(R.landing(b, 3, 3, 0), 3, "lands on top of a disc")
	check_eq(R.landing(b, 3, 3, 1), 7, "falls to the floor")
	check_eq(R.landing(b, 3, 3, 2), 5, "stacks on a block")
	b = R.from_rows(["o..", "x..", "x.."])
	check_eq(R.landing(b, 3, 3, 0), -1, "a full column takes nothing")
	check_cells(Array(R.moves(b, 3)), [1, 2], "only open columns are moves")


func test_drops_flip_trapped_lines_any_way() -> void:
	var b := R.from_rows([".......", ".......", ".......", ".......", "..oo...", ".xox..."])
	var made := R.drop(b, 7, 6, 3, 0)
	check_cells(Array(made.flipped), [31, 30], "down and down-left both flip")
	check_eq(R.count(b, 0), 5, "the drop and two flips are Sun's")
	check(made.locked.is_empty(), "three in a row doesn't lock")


func test_four_in_a_row_locks_and_locked_discs_never_flip() -> void:
	var b := R.from_rows([".......", ".......", ".......", ".......", ".xo....", "xoo...."])
	var made := R.drop(b, 7, 6, 3, 0)
	check_cells(Array(made.locked), [35, 36, 37, 38], "the bottom row locks")
	check(R.is_locked(b[36]), "a flipped disc in the line is locked")
	# Ice can't flip a locked line back, and a locked Sun disc is a wall.
	b = R.from_rows(["....", "....", "XXo.", "oXXX"])
	var flips := R.flips(b, 4, 4, 11, 1)
	check(flips.is_empty(), "locked discs stop a flip")
	check_eq(R.count(b, 0), 5, "locked discs still count")


func test_a_full_rack_goes_to_the_most_discs() -> void:
	var m := _match(["xo.", "oxo", "xox"])
	var result := m.drop(2)
	check(result.round_over, "the rack is full")
	check_eq(result.winner, 0, "Sun has more discs")
	check_eq(m.rounds_won, 1, "a round won")
	check(m.scores[0] >= FlipMatch.ROUND_POINTS, "the round bonus is paid")


func test_losing_costs_a_heart_and_replays() -> void:
	var m := _match(["ox.", "xox", "oxo"])
	m.turn = 1
	var result := m.drop(2)
	check_eq(result.winner, 1, "the CPU wins")
	check_eq(m.hearts, FlipMatch.HEARTS - 1, "a heart lost")
	m.next_round()
	check_eq(m.round, 1, "the round replays")
	check(m.is_running(), "a new round starts")


func test_rounds_get_harder() -> void:
	check_eq(FlipMatch.board_shape(1), Vector2i(7, 6), "a classic rack first")
	check_eq(FlipMatch.board_shape(6), Vector2i(8, 7), "a bigger rack later")
	check(FlipMatch.block_pairs(1) == 0 and FlipMatch.block_pairs(4) > 0, "blocks arrive")
	check(FlipMatch.cpu_config(7).depth > FlipMatch.cpu_config(1).depth, "the CPU looks deeper")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var blocks := R.make_blocks(7, 6, 2, rng)
	check_eq(blocks.size(), 4, "blocks come in mirrored pairs")
	for i in blocks:
		check(blocks.has(i / 7 * 7 + 6 - i % 7), "each block has its mirror")


func test_streaks_points_and_powers() -> void:
	var m := _match([".......", ".......", ".......", ".......", ".xo....", "xoo...."])
	var result := m.drop(3)
	check(result.combo, "a lock is a combo")
	check_eq(result.points, FlipMatch.DROP_POINTS + FlipMatch.FLIP_POINTS * 2 + FlipMatch.LOCK_POINTS * 4,
		"drop, flips and locks score")
	m.charges[0] = 1
	m.turn = 0
	check(m.can_undo(), "UNDO is ready on your turn")
	check(m.undo(), "UNDO takes the move back")
	check_eq(R.count(m.board, 0), 2, "the board is as it was")
	check_eq(m.charges[0], 0, "UNDO spends a charge")


func test_cpu_takes_a_lock_and_blocks_yours() -> void:
	var rng := RandomNumberGenerator.new()
	# Ice to move: dropping in column 3 flips two and locks four in a row.
	var b := R.from_rows([".......", ".......", ".......", ".......", ".ox....", "oxx...."])
	check_eq(FlipAI.choose(b, 7, 6, 1, 3, 0.0, 0, rng), 3, "the CPU takes the big lock")
	var t := Time.get_ticks_msec()
	FlipAI.choose(R.new_board(7, 6), 7, 6, 1, 4, 0.0, 8, rng)
	check(Time.get_ticks_msec() - t < 3000, "a depth-4 move stays quick")


func test_two_players_play_to_two_rounds() -> void:
	var m := FlipMatch.new(3, false)
	m.start()
	check_eq(m.w, 7, "two players use the classic rack")
	m.set_board(R.from_rows(["xo.", "oxo", "xox"]), 3)
	m.turn = 0
	m.drop(2)
	check_eq(m.round_wins[0], 1, "Sun takes a round")
	check(not m.game_over, "first to two")
	m.next_round()
	check_eq(m.starter, 1, "Ice starts the next round")
