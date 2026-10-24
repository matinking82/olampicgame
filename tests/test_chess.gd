extends "res://tests/test_case.gd"
## Merge Mate: moves, merges, check, mate, spawns, scoring and the CPU.

const R := preload("res://chess/chess_rules.gd")


static func at(x: int, y: int) -> int:
	return R.idx(x, y)


func _match(rows: Array, to_move: int = 0) -> ChessMatch:
	var m := ChessMatch.new(7)
	m.start()
	m.cells = R.from_rows(rows)
	m.turn = to_move
	return m


func test_pawn_steps_forward_and_captures_diagonally() -> void:
	var cells := R.from_rows(["....k...", "", "", "", "..p.....", "...P....", "", "....K..."])
	var t := R.targets(cells, at(3, 5))
	check(t.has(at(3, 4)), "steps forward")
	check(t.has(at(2, 4)), "captures diagonally")
	check_eq(t.size(), 2, "nothing else")
	var blocked := R.from_rows(["....k...", "", "", "", "...p....", "...P....", "", "....K..."])
	check_eq(R.targets(blocked, at(3, 5)).size(), 0, "a pawn can't capture straight ahead")


func test_side_one_pawns_walk_down() -> void:
	var cells := R.from_rows(["....k...", "...p....", "", "", "", "", "", "....K..."])
	check(R.targets(cells, at(3, 1)).has(at(3, 2)), "top pawns move down the board")


func test_twins_merge_when_touching() -> void:
	var cells := R.from_rows(["....k...", "", "", "", "", "....P...", "...P....", "....K..."])
	check(R.targets(cells, at(3, 6)).has(at(4, 5)), "diagonal neighbours merge")
	var apart := R.from_rows(["....k...", "", "", "", "P.......", "", "...P....", "....K..."])
	check(not R.targets(apart, at(3, 6)).has(at(0, 4)), "pawns far apart don't")


func test_sliders_merge_at_range_but_not_through_pieces() -> void:
	var cells := R.from_rows(["....k...", "", "R......R", "", "", "", "", "....K..."])
	check(R.targets(cells, at(0, 2)).has(at(7, 2)), "a rook reaches its twin along the row")
	var blocked := R.from_rows(["....k...", "", "R..P...R", "", "", "", "", "....K..."])
	check(not R.targets(blocked, at(0, 2)).has(at(7, 2)), "not through another piece")


func test_merge_tiers() -> void:
	var cells := R.from_rows(["....k...", "", "", "...NB...", "", "", "", "....K..."])
	check(R.targets(cells, at(3, 3)).has(at(4, 3)), "knight and bishop share a tier")
	check_eq(R.merged_type(R.PAWN, 0.2), R.KNIGHT, "a low roll makes a knight")
	check_eq(R.merged_type(R.PAWN, 0.8), R.BISHOP, "a high roll makes a bishop")
	check_eq(R.merged_type(R.BISHOP), R.ROOK, "minors make a rook")
	check_eq(R.merged_type(R.ROOK), R.QUEEN, "rooks make a queen")
	check_eq(R.merged_type(R.QUEEN), R.EMPRESS, "queens make an empress")
	check(not R.can_merge(R.piece(R.EMPRESS, 0), R.piece(R.EMPRESS, 0)), "the empress is the top")
	check(not R.can_merge(R.piece(R.KING, 0), R.piece(R.KING, 0)), "kings never merge")
	check(not R.can_merge(R.piece(R.PAWN, 0), R.piece(R.PAWN, 1)), "enemies never merge")
	check(not R.can_merge(R.piece(R.PAWN, 0), R.piece(R.ROOK, 0)), "different tiers don't")


func test_pawn_promotes_to_queen() -> void:
	var cells := R.from_rows(["....k...", "P.......", "", "", "", "", "", "....K..."])
	var next := R.apply(cells, at(0, 1), at(0, 0))
	check_eq(next[at(0, 0)], R.piece(R.QUEEN, 0), "reaching the far row makes a queen")


func test_empress_moves_like_queen_and_knight() -> void:
	var cells := R.from_rows(["k.......", "", "", "...E....", "", "", "", "....K..."])
	var t := R.targets(cells, at(3, 3))
	check(t.has(at(4, 5)), "knight jump")
	check(t.has(at(3, 0)), "rook line")
	check(t.has(at(6, 6)), "bishop line")


func test_pinned_piece_stays_on_the_line() -> void:
	var cells := R.from_rows(["....r...", "", "", "", "", "....R...", "", "....K..."])
	var t := R.legal_targets(cells, at(4, 5))
	check(not t.has(at(3, 5)), "can't step off the pin")
	check(t.has(at(4, 0)), "can capture the pinner")
	check(t.has(at(4, 3)), "can slide along the pin")


func test_back_rank_mate_wins_the_round() -> void:
	var m := _match(["k.......", "pp......", "", "", "", "", "", "....K..R"])
	var result := m.act(at(7, 7), at(7, 0))
	check(result.mate, "the rook mates")
	check_eq(m.winner, 0, "side 0 wins")
	check(result.round_bonus > 0, "the round pays a bonus")
	check(not m.game_over, "against the CPU the run goes on")
	m.next_round()
	check_eq(m.round, 2, "next round")
	check_eq(m.winner, -1, "fresh round")
	check_eq(R.king_square(m.cells, 1), at(4, 0), "new board")


func test_losing_to_the_cpu_ends_the_run() -> void:
	var m := _match(["....k..r", "", "", "", "", "", "PP......", "K......."], 1)
	var result := m.act(at(7, 0), at(7, 7))
	check(result.mate, "the CPU mates")
	check(m.game_over, "the run is over")


func test_merge_scores_and_starts_a_streak() -> void:
	var m := _match(["....k...", "", "", "", "", "....P...", "...P....", "....K..."])
	var result := m.act(at(3, 6), at(4, 5))
	check_eq(result.kind, "merge", "it's a merge")
	var type := R.type_of(m.cells[at(4, 5)])
	check(type == R.KNIGHT or type == R.BISHOP, "two pawns make a knight or bishop")
	check_eq(m.cells[at(3, 6)], R.EMPTY, "the dragged pawn is gone")
	check_eq(result.points, ChessMatch.MERGE_POINTS[2], "merge points")
	check_eq(m.streak[0], 1, "streak started")
	check_eq(m.turn, 1, "turn passes")


func test_capture_and_check_points() -> void:
	var m := _match(["....k...", "", ".....q..", "", "", "", "", "R...K..."])
	m.spawn_chance = [0.0, 0.0]
	var result := m.act(at(0, 7), at(0, 2))
	check_eq(result.kind, "move", "a plain move")
	check_eq(result.points, 0, "no points for a plain move")
	m.act(at(5, 2), at(5, 3))
	result = m.act(at(0, 2), at(0, 0))
	check(result.check, "rook gives check on the back row")
	check_eq(result.base, ChessMatch.CHECK_POINTS, "check points")


func test_streak_survives_quiet_turns_up_to_the_grace() -> void:
	var m := ChessMatch.new(3)
	m.start()
	m._award(0, 100)
	for i in ChessMatch.STREAK_GRACE:
		m._award(0, 0)
	check_eq(m.streak[0], 1, "streak kept through the grace")
	m._award(0, 0)
	check_eq(m.streak[0], 0, "and lost after it")
	for i in ChessMatch.FEVER_STREAK:
		m._award(0, 100)
	check(m.is_fever(0), "fever at a long streak")


func test_spawns_land_on_home_rows() -> void:
	var m := ChessMatch.new(11)
	m.start()
	m.spawn_chance = [1.0, 1.0]
	var spawned := 0
	for i in 6:
		var moves := R.legal_moves(m.cells, m.turn)
		var mv := moves[0]
		var side := m.turn
		var result := m.act(R.move_from(mv), R.move_to(mv))
		if result.spawn >= 0:
			spawned += 1
			check(R.home_rows(side).has(result.spawn / 8), "spawn on the mover's home rows")
			check_eq(R.side_of(m.cells[result.spawn]), side, "spawn belongs to the mover")
	check(spawned >= 5, "spawns happen when there's room")


func test_upgrade_raises_a_tier_without_using_the_turn() -> void:
	var m := _match(["....k...", "", "", "", "", "", "...P....", "....K..."])
	check(not m.can_upgrade(at(3, 6)), "needs a charge")
	m.charges[0] = 1
	check(not m.can_upgrade(at(4, 7)), "kings can't be upgraded")
	var result := m.upgrade(at(3, 6))
	check_eq(R.TIER[R.type_of(m.cells[at(3, 6)])], 2, "pawn became a minor piece")
	check_eq(m.charges[0], 0, "charge spent")
	check_eq(m.turn, 0, "still your turn")
	check(not result.mate, "no mate")


func test_points_fill_the_upgrade_meter() -> void:
	var m := ChessMatch.new(3)
	m.start()
	var award := m._award(0, ChessMatch.METER_GOAL)
	check_eq(award.charges_earned, 1, "a full meter gives a charge")
	check_eq(m.charges[0], 1, "charge stored")


func test_stalemated_side_passes() -> void:
	var m := _match(["k.......", "", "..Q.....", "", "", "", "", ".......K"])
	m.spawn_chance = [0.0, 0.0]
	var result := m.act(at(2, 2), at(2, 1))
	check(result.passed, "boxed-in king passes")
	check(not result.mate, "not a mate")
	check_eq(m.turn, 0, "the mover goes again")


func test_cpu_takes_mate_in_one() -> void:
	var cells := R.from_rows(["k.......", "pp......", "", "", "", "", "", "....K..R"])
	check_eq(ChessAI.choose(cells, 0, 2), R.encode(at(7, 7), at(7, 0)), "finds the back-rank mate")


func test_cpu_grabs_a_free_queen() -> void:
	var cells := R.from_rows(["....k...", "", "..n.....", "", "...Q....", "", "", "....K..."])
	check_eq(ChessAI.choose(cells, 1, 2), R.encode(at(2, 2), at(3, 4)), "knight takes the queen")


func test_cpu_saves_its_hanging_queen() -> void:
	# The pawn attacks the queen; the CPU should move it somewhere safe.
	var cells := R.from_rows(["....k...", "", "...q....", "....P...", "", "", "", "....K..."])
	var m := ChessAI.choose(cells, 1, 2)
	var next := R.apply(cells, R.move_from(m), R.move_to(m))
	var q := R.king_square(next, 1)
	check(q >= 0, "still has a king")
	var queen_at := -1
	for i in R.CELLS:
		if next[i] == R.piece(R.QUEEN, 1):
			queen_at = i
	check(queen_at >= 0 and not R.is_attacked(next, queen_at, 0), "queen ends up safe (or took the pawn)")


func test_cpu_games_finish_cleanly() -> void:
	for g in 2:
		var m := ChessMatch.new(100 + g, false)
		m.start()
		var guard := 0
		while not m.game_over and guard < ChessMatch.MAX_PLIES + 5:
			var mv := ChessAI.choose(m.cells, m.turn, 1, 80.0, m.rng)
			if mv < 0:
				break
			m.act(R.move_from(mv), R.move_to(mv))
			guard += 1
		check(m.game_over, "game %d ends (mate or draw) within the ply limit" % g)
