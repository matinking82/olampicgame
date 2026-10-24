extends "res://tests/test_case.gd"


func _state(rows: Array, pieces: Array) -> GameState:
	var s := GameState.new(42)
	s.board = Board.from_rows(rows)
	s.tray = pieces
	return s


func _stones_except(open: Array) -> Array:
	var rows := []
	for y in 9:
		var row := ""
		for x in 9:
			row += "." if open.has(Vector2i(x, y)) else "#"
		rows.append(row)
	return rows


func test_start_seeds_board_and_deals() -> void:
	var s := GameState.new(7)
	s.start()
	check_eq(s.board.count_tiles(), GameState.SEED_TILES, "seed tiles")
	check(Rules.find_groups(s.board).is_empty(), "no ready-made pops")
	for p in s.tray:
		check(p != null, "tray slot filled")
	check(not s.game_over, "playable")


func test_same_seed_same_run() -> void:
	var a := GameState.new(99)
	var b := GameState.new(99)
	a.start()
	b.start()
	check_eq(a.board.cells, b.board.cells, "board")
	for i in 3:
		check_eq(a.piece(i).offsets, b.piece(i).offsets, "piece %d shape" % i)
		check_eq(a.piece(i).values, b.piece(i).values, "piece %d values" % i)


func test_place_scores_and_empties_the_slot() -> void:
	var s := _state([], [mono(1), mono(2), mono(3)])
	var r := s.place(0, v(0, 0))
	check_eq(r.points, 1, "one point per cell")
	check_eq(s.score, 1, "score")
	check(s.tray[0] == null, "slot used")
	check(s.place(0, v(1, 1)).is_empty(), "empty slot can't be placed")
	check(s.place(1, v(0, 0)).is_empty(), "occupied cell refused")


func test_tray_refills_after_three() -> void:
	var s := _state([], [mono(1), mono(2), mono(3)])
	s.place(0, v(0, 0))
	s.place(1, v(4, 4))
	var r := s.place(2, v(8, 8))
	check(r.dealt, "dealt")
	for p in s.tray:
		check(p != null, "new piece")


func test_streak_builds_into_fever() -> void:
	var s := _state(["33......."], [mono(3), mono(7), mono(8)])
	s.streak = Scoring.FEVER_STREAK - 1
	var r := s.place(0, v(2, 0))
	check_eq(r.streak, Scoring.FEVER_STREAK, "streak")
	check(r.fever, "fever")
	check_eq(r.points, 1 + roundi(30 * Scoring.streak_mult(Scoring.FEVER_STREAK)), "fever points")


func test_streak_survives_quiet_moves_then_breaks() -> void:
	var s := _state([], [mono(7), mono(8), mono(9)])
	s.streak = 3
	var quiet := s.place(0, v(0, 0))
	check_eq(quiet.streak, 3, "one quiet move keeps it")
	check_eq(s.misses, 1, "miss counted")
	s.misses = Scoring.STREAK_GRACE - 1
	var last := s.place(1, v(8, 8))
	check_eq(last.streak, 0, "too many quiet moves break it")
	check_eq(s.misses, 0, "misses reset")


func test_a_clear_resets_the_misses() -> void:
	var s := _state(["33......."], [mono(3), mono(7), mono(8)])
	s.streak = 2
	s.misses = 2
	s.place(0, v(2, 0))
	check_eq(s.streak, 3, "streak grows")
	check_eq(s.misses, 0, "misses cleared")


func test_pop_of_four_grants_a_laser() -> void:
	var s := _state(["333......"], [mono(3), mono(1), mono(2)])
	var r := s.place(0, v(3, 0))
	check_eq(s.powers.slots, [Powers.Kind.LASER] as Array[int], "laser")
	check_eq(r.powers_earned, [Powers.Kind.LASER] as Array[int], "reported")
	check_eq(s.board.get_cell(v(3, 0)), 4, "merged")


func test_full_slots_pay_points_instead() -> void:
	var s := _state(["333......"], [mono(3), mono(1), mono(2)])
	for i in 3:
		s.powers.add(Powers.Kind.BOMB)
	var r := s.place(0, v(3, 0))
	check_eq(r.overflow, 1, "overflow")
	check_eq(r.points, 1 + 80 + Powers.OVERFLOW_POINTS, "points")


func test_blast_puts_a_wild_in_the_next_deal() -> void:
	var s := _state(["12345678."], [mono(9), mono(1), mono(2)])
	s.place(0, v(8, 0))
	check_eq(s.powers.pending_wilds, 1, "wild owed")
	s.place(1, v(0, 5))
	s.place(2, v(5, 5))
	check_eq(s.powers.pending_wilds, 0, "wild delivered")
	check(s.piece(0).has_wild(), "first piece has a wild")


func test_power_meter_pays_a_hammer() -> void:
	var s := _state(["12345678."], [mono(9), mono(1), mono(2)])
	s.powers.meter = Powers.METER_GOAL - 100
	var r := s.place(0, v(8, 0))
	check(r.powers_earned.has(Powers.Kind.HAMMER), "hammer from the meter")


func test_dead_end_ends_the_run() -> void:
	var s := _state(_stones_except([v(0, 0), v(8, 8)]), [mono(1), domino(1, 2), domino(3, 4)])
	var r := s.place(0, v(0, 0))
	check(r.game_over, "nothing fits")
	check(s.game_over, "state")
	check(s.place(1, v(8, 8)).is_empty(), "no moves after game over")


func test_held_power_keeps_the_run_alive() -> void:
	var s := _state(_stones_except([v(0, 0), v(8, 8)]), [mono(1), domino(1, 2), domino(3, 4)])
	s.powers.add(Powers.Kind.HAMMER)
	var r := s.place(0, v(8, 8))
	check(not r.game_over, "hammer can still help")
	check(s.is_stuck(), "but stuck")
	var h := s.use_power(0, v(1, 0))
	check_cells(h.broken, [v(1, 0)], "hammer smashed a stone")
	check(not s.game_over, "domino fits now")


func test_last_useless_power_ends_the_run() -> void:
	var s := _state(_stones_except([v(0, 0), v(8, 8)]), [mono(1), domino(1, 2), domino(3, 4)])
	s.powers.add(Powers.Kind.BOMB)
	s.place(0, v(0, 0))
	var r := s.use_power(0, v(4, 4))
	check_eq(r.cracked.size(), 9, "bomb only cracks stones")
	check(r.game_over, "still no room")


func test_bomb_clears_its_area() -> void:
	var s := _state(["", "", "", "...123...", "...456...", "...789..."], [mono(1), mono(2), mono(3)])
	s.powers.add(Powers.Kind.BOMB)
	var r := s.use_power(0, v(4, 4))
	check_eq(r.cleared.size(), 9, "cleared")
	check_eq(s.board.count_tiles(), 0, "board empty")
	check(r.perfect, "perfect board")
	check_eq(r.points, 90 + Scoring.PERFECT_POINTS, "points")
	check(not s.powers.slots.has(Powers.Kind.BOMB), "power used")


func test_nuke_removes_one_digit() -> void:
	var s := _state(["1.1.1.2..", "...1....."], [mono(1), mono(2), mono(3)])
	s.powers.add(Powers.Kind.NUKE)
	check(s.use_power(0, v(1, 0)).is_empty(), "needs a digit target")
	var r := s.use_power(0, v(0, 0))
	check_eq(r.cleared.size(), 4, "all the 1s")
	check_eq(s.board.get_cell(v(6, 0)), 2, "other digits stay")


func test_laser_clears_row_and_column() -> void:
	var s := _state(["1.2", "3..", "4.."], [mono(1), mono(2), mono(3)])
	s.powers.add(Powers.Kind.LASER)
	var r := s.use_power(0, v(0, 0))
	check_eq(r.cleared.size(), 4, "row 1 and column 1")
	check_eq(s.board.count_tiles(), 0, "nothing left")


func test_reroll_deals_a_new_tray() -> void:
	var s := _state([], [mono(1), null, null])
	s.powers.add(Powers.Kind.REROLL)
	s.use_power(0)
	for p in s.tray:
		check(p != null, "full tray")


func test_preview_changes_nothing() -> void:
	var s := _state(["33......."], [mono(3), mono(1), mono(2)])
	var pv := s.preview(0, v(2, 0))
	check_eq(pv.steps.size(), 1, "preview sees the pop")
	check_eq(s.board.get_cell(v(2, 0)), Board.EMPTY, "board untouched")
	check(s.tray[0] != null, "tray untouched")
	check(s.preview(0, v(0, 0)).is_empty(), "invalid spot")


func test_level_up_is_reported() -> void:
	var s := _state([], [mono(9), mono(1), mono(2)])
	s.turns = Difficulty.threshold(2) - 1
	var r := s.place(0, v(8, 0))
	check(r.level_up, "level up")
	check_eq(s.level, 2, "level")
	check(not s.place(1, v(0, 0)).level_up, "no level up the turn after")
