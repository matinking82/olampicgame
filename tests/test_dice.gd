extends "res://tests/test_case.gd"
## Tic Tac Roll: dice categories, claiming and stealing, lines, turns,
## rounds, hearts, powers and the CPU.

const R := preload("res://dice/dice_rules.gd")
const C := DiceRules.Cat


static func dice(values: Array) -> PackedInt32Array:
	return PackedInt32Array(values)


## A match on a known board (the tutorial's) with the player to move.
func _match(against_cpu: bool = true) -> DiceMatch:
	var m := DiceMatch.new(11, against_cpu)
	m.start()
	m.cats = PackedInt32Array([
		C.CHANCE, C.FIVES, C.SMALL_STRAIGHT, C.TWOS,
		C.THREES, C.FULL_HOUSE, C.TWO_PAIRS, C.SIXES,
		C.FOUR_KIND, C.THREE_KIND, C.BIG_STRAIGHT, C.ONES,
		C.FOURS, C.FIVE_KIND, C.THREE_KIND, C.CHANCE,
	])
	return m


func _roll(m: DiceMatch, values: Array) -> void:
	m.rigged.assign(values)
	m.roll()


func test_scores_each_category() -> void:
	var fh := dice([3, 3, 5, 5, 5])
	check_eq(R.score(C.FIVES, fh), 15, "three 5s")
	check_eq(R.score(C.THREES, fh), 6, "a pair of 3s counts")
	check_eq(R.score(C.ONES, fh), -1, "no 1s")
	check_eq(R.score(C.SIXES, dice([6, 1, 2, 3, 4])), -1, "a single 6 isn't enough")
	check_eq(R.score(C.FULL_HOUSE, fh), 25, "full house")
	check_eq(R.score(C.THREE_KIND, fh), 21, "3 of a kind scores the sum")
	check_eq(R.score(C.FOUR_KIND, fh), -1, "not 4 of a kind")
	check_eq(R.score(C.TWO_PAIRS, fh), 21, "a full house has two pairs")
	check_eq(R.score(C.TWO_PAIRS, dice([4, 4, 4, 4, 2])), -1, "four of one face is one pair")
	check_eq(R.score(C.CHANCE, dice([1, 1, 2, 2, 3])), 9, "chance is the sum")
	check_eq(R.score(C.SMALL_STRAIGHT, dice([3, 4, 1, 2, 2])), 30, "small straight 1-4")
	check_eq(R.score(C.SMALL_STRAIGHT, dice([3, 4, 5, 6, 6])), 30, "small straight 3-6")
	check_eq(R.score(C.SMALL_STRAIGHT, dice([1, 2, 3, 5, 6])), -1, "a gap breaks it")
	check_eq(R.score(C.BIG_STRAIGHT, dice([2, 3, 4, 5, 6])), 40, "big straight")
	check_eq(R.score(C.BIG_STRAIGHT, dice([1, 2, 3, 4, 4])), -1, "four in a row isn't big")
	check_eq(R.score(C.FIVE_KIND, dice([2, 2, 2, 2, 2])), 50, "five of a kind")
	check_eq(R.score(C.FULL_HOUSE, dice([2, 2, 2, 2, 2])), 25, "five of a kind is also a full house")
	check_eq(R.score(C.FOUR_KIND, dice([2, 2, 2, 2, 2])), 10, "and four of a kind")


func test_lines_are_four_in_a_row() -> void:
	check_eq(R.lines().size(), 10, "4 rows, 4 columns, 2 diagonals")
	var owners := PackedInt32Array()
	owners.resize(R.CELLS)
	owners.fill(R.NONE)
	for i: int in [3, 6, 9, 12]:
		owners[i] = 1
	var line := Array(R.winning_line(owners, 1))
	line.sort()
	check_eq(line, [3, 6, 9, 12], "the anti-diagonal")
	check(R.winning_line(owners, 0).is_empty(), "the other side has nothing")


func test_nothing_to_claim_before_rolling() -> void:
	var m := _match()
	check(m.options().is_empty(), "no options before the first roll")
	check(m.claim(0).is_empty(), "no claim before the first roll")
	check(not m.toggle_hold(0), "no holding before the first roll")


func test_held_dice_stay_and_rolls_run_out() -> void:
	var m := _match()
	_roll(m, [4, 4, 2, 4, 6])
	m.toggle_hold(0)
	m.toggle_hold(1)
	m.toggle_hold(3)
	_roll(m, [2, 2])
	check_eq(m.dice, dice([4, 4, 2, 4, 2]), "held dice keep their faces")
	_roll(m, [1, 1])
	check_eq(m.rolls_left, 0, "three rolls a turn")
	check(not m.can_roll(), "no fourth roll")
	check(m.roll().is_empty(), "rolling does nothing")


func test_claim_marks_cell_and_passes_turn() -> void:
	var m := _match()
	_roll(m, [4, 4, 2, 4, 2])
	check(m.can_claim(5), "full house fits")
	check(not m.can_claim(2), "small straight doesn't")
	var r := m.claim(5)
	check_eq(r.value, 25, "scored 25")
	check_eq(r.points, 250, "points are ten times the dice")
	check_eq(m.owners[5], 0, "the cell is ours")
	check_eq(m.marks[5], 25, "with its score")
	check_eq(m.turn, 1, "the turn passes")
	check(not m.rolled, "the new turn starts unrolled")


func test_steal_needs_a_higher_score() -> void:
	var m := _match()
	m.owners[9] = 1
	m.marks[9] = 12
	_roll(m, [2, 2, 2, 1, 5])
	check(not m.can_claim(9), "12 doesn't beat 12")
	m.rolls_left = 1
	m.rigged.assign([6])
	m.held = [true, true, true, true, false]
	m.roll()
	check(m.can_claim(9), "13 beats 12")
	var r := m.claim(9)
	check(r.stolen, "it was a steal")
	check_eq(r.points, 130 + DiceMatch.STEAL_POINTS, "steals pay extra")
	check_eq(m.owners[9], 0, "now ours")


func test_fixed_cells_cannot_be_stolen() -> void:
	var m := _match()
	m.owners[5] = 1
	m.marks[5] = 25
	_roll(m, [3, 3, 3, 6, 6])
	check(not m.can_claim(5), "a full house can't beat a full house")


func test_four_in_a_row_wins_the_round() -> void:
	var m := _match()
	for i: int in [8, 10, 11]:
		m.owners[i] = 0
	m.owners[9] = 1
	m.marks[9] = 12
	_roll(m, [6, 6, 6, 5, 3])
	var r := m.claim(9)
	check_eq(r.line, PackedInt32Array([8, 9, 10, 11]), "the row")
	check_eq(m.winner, 0, "the player wins")
	check(r.round_bonus > 0, "with a round bonus")
	check_eq(m.rounds_won, 1, "counted")
	m.next_round()
	check_eq(m.round, 2, "next round")
	check_eq(m.winner, -1, "a fresh round")
	check_eq(R.count_owned(m.owners, 0), 0, "a clear board")


func test_losing_costs_a_heart_and_replays() -> void:
	var m := _match()
	for k in DiceMatch.HEARTS:
		m.turn = 1
		m.cats[3] = C.TWOS
		for i: int in [0, 1, 2]:
			m.owners[i] = 1
		m.rigged.assign([2, 2, 1, 3, 4])
		m.roll()
		m.claim(3)
		check_eq(m.winner, 1, "the CPU wins")
		check_eq(m.hearts, DiceMatch.HEARTS - k - 1, "a heart lost")
		if not m.game_over:
			m.next_round()
			check_eq(m.round, 1, "the round is replayed")
			check_eq(m.turn, 0, "the player starts again")
	check(m.game_over, "out of hearts")


func test_bust_passes_the_turn() -> void:
	var m := _match()
	for i in R.CELLS:
		m.owners[i] = 1
		m.marks[i] = 50
	m.owners[0] = R.NONE
	m.cats[0] = C.FIVE_KIND
	_roll(m, [1, 2, 3, 4, 6])
	check(not m.is_bust(), "not a bust while rolls remain")
	_roll(m, [1, 2, 3, 4, 6])
	_roll(m, [1, 2, 3, 4, 6])
	check(m.is_bust(), "a bust after the last roll")
	var r := m.pass_turn()
	check(r.bust, "passed")
	check_eq(m.turn, 1, "the CPU's turn")


func test_full_board_goes_to_most_cells() -> void:
	var m := _match()
	# Pairs of cells alternate, so nobody has a line; the last cell decides it.
	for i in R.CELLS:
		m.owners[i] = ((i % 4) / 2 + i / 4) % 2
		m.marks[i] = 50
	m.owners[2] = R.NONE
	check(R.winning_line(m.owners, 0).is_empty() and R.winning_line(m.owners, 1).is_empty(), "no lines yet")
	m.cats[2] = C.CHANCE
	_roll(m, [1, 1, 1, 1, 2])
	var r := m.claim(2)
	check(r.full, "the board filled")
	check(m.full_board, "decided on the board")
	check_eq(m.winner, 0, "8 + 1 cells beats 7")


func test_two_players_play_first_to_three() -> void:
	var m := _match(false)
	for k in DiceMatch.MATCH_ROUNDS:
		# Sun wins every round, whoever starts it.
		var side := 0
		m.turn = side
		m.cats[3] = C.TWOS
		for i: int in [0, 1, 2]:
			m.owners[i] = side
		m.rigged.assign([2, 2, 3, 3, 1])
		m.roll()
		m.claim(3)
		check_eq(m.winner, side, "the mover takes the round")
		if k < DiceMatch.MATCH_ROUNDS - 1:
			check(not m.game_over, "the match goes on")
			var starter := m.starter
			m.next_round()
			check_eq(m.starter, 1 - starter, "starters alternate")
	check(m.game_over, "first to three")


func test_streak_counts_combos_not_chance() -> void:
	var m := _match()
	_roll(m, [4, 4, 2, 4, 2])
	var r := m.claim(5)
	check(r.combo, "a full house is a combo")
	check_eq(m.streak[0], 1, "the streak grows")
	m.turn = 0
	m.rolled = false
	m.rolls_left = 3
	_roll(m, [1, 2, 3, 5, 6])
	r = m.claim(0)
	check(not r.combo, "chance is quiet")
	check_eq(m.streak[0], 1, "one quiet turn is forgiven")


func test_points_earn_power_charges() -> void:
	var m := _match()
	m.meter[0] = DiceMatch.METER_GOAL - 10
	_roll(m, [4, 4, 2, 4, 2])
	var r := m.claim(5)
	check_eq(r.charges_earned, 1, "a charge")
	check_eq(m.charges[0], 1, "banked")


func test_extra_roll_and_nudge() -> void:
	var m := _match()
	m.charges[0] = 2
	_roll(m, [1, 2, 3, 4, 6])
	check(m.nudge(4), "nudge works")
	check_eq(m.dice[4], 1, "6 wraps to 1")
	check(m.extra_roll(), "extra roll works")
	check_eq(m.rolls_left, 3, "one more roll")
	check_eq(m.charges[0], 0, "both charges spent")
	check(not m.extra_roll(), "no charges left")


func test_cpu_takes_the_winning_cell() -> void:
	var m := _match()
	for i: int in [8, 10, 11]:
		m.owners[i] = 1
	var cfg := {"samples": 10, "noise": 0.0, "block": 1.0}
	var d := DiceAI.decide(m.cats, m.owners, m.marks, 1, dice([6, 6, 6, 5, 3]), 2, cfg, m.rng)
	check_eq(d.get("claim", -1), 9, "it completes the row")


func test_cpu_blocks_a_threat() -> void:
	var m := _match()
	for i: int in [8, 10, 11]:
		m.owners[i] = 0
	var cfg := {"samples": 10, "noise": 0.0, "block": 1.0}
	var d := DiceAI.decide(m.cats, m.owners, m.marks, 1, dice([6, 6, 6, 5, 3]), 0, cfg, m.rng)
	check_eq(d.get("claim", -1), 9, "it takes the cell the player needs")


func test_cpu_steals_to_win() -> void:
	var m := _match()
	for i: int in [8, 10, 11]:
		m.owners[i] = 1
	m.owners[9] = 0
	m.marks[9] = 12
	var cfg := {"samples": 10, "noise": 0.0, "block": 1.0}
	var d := DiceAI.decide(m.cats, m.owners, m.marks, 1, dice([6, 6, 6, 5, 3]), 0, cfg, m.rng)
	check_eq(d.get("claim", -1), 9, "it steals the last cell of its row")


func test_cpu_rerolls_junk() -> void:
	var m := _match()
	var cfg := {"samples": 20, "noise": 0.0, "block": 1.0}
	var d := DiceAI.decide(m.cats, m.owners, m.marks, 1, dice([6, 6, 6, 6, 1]), 2, cfg, m.rng)
	check(d.has("hold"), "four 6s with rolls left: go for more")
	if d.has("hold"):
		check(d.hold[0] and d.hold[1] and d.hold[2] and d.hold[3], "keeping the 6s")
