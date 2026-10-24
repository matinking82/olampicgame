extends "res://tests/test_case.gd"
## Mine Fleet: fleets that never touch, numbers, calm water opening up,
## hits, sinkings, turns, rounds, powers and the CPU gunner.

const R := preload("res://fleet/fleet_rules.gd")
const ENEMY := [".......", "...aaa.", ".......", "......d", ".......", "b..cc..", "b......"]
const HOME := ["aaa....", ".......", "....b..", "d...b..", ".......", ".cc....", "......."]


func _match() -> FleetMatch:
	var m := FleetMatch.new(5)
	m.start()
	m.set_fleets(R.fleet_from_rows(HOME), R.fleet_from_rows(ENEMY))
	m.turn = 0
	return m


func _blank(n: int) -> PackedInt32Array:
	var s := PackedInt32Array()
	s.resize(n * n)
	return s


func test_fleets_are_placed_without_touching() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for k in 20:
		var fleet := R.place_fleet(9, [5, 4, 3, 2, 2, 1], rng)
		check_eq(R.ship_count(fleet), 6, "every ship is placed")
		for i in fleet.size():
			if fleet[i] == R.SEA:
				continue
			for m in R.neighbours(9, i):
				check(fleet[m] == R.SEA or fleet[m] == fleet[i], "ships never touch")


func test_numbers_count_ship_squares_around() -> void:
	var fleet := R.fleet_from_rows(ENEMY)
	check_eq(R.number(fleet, 7, 2 * 7 + 4), 3, "under the long ship")
	check_eq(R.number(fleet, 7, 2 * 7 + 1), 0, "calm water")
	check_eq(R.line_counts(fleet, 7, 7 + 3), Vector2i(3, 2), "SONAR counts a row and a column")


func test_calm_water_opens_up() -> void:
	var fleet := R.fleet_from_rows(ENEMY)
	var seen := _blank(7)
	var shot := R.fire(fleet, seen, 7, 15)
	check(not shot.hit, "a miss")
	check(shot.opened.size() > 10, "a zero opens the sea round it")
	for c in shot.opened:
		check_eq(fleet[c], R.SEA, "only water opens")


func test_hits_sink_ships_and_open_their_ring() -> void:
	var fleet := R.fleet_from_rows(ENEMY)
	var seen := _blank(7)
	check(R.fire(fleet, seen, 7, 10).hit, "a hit")
	check_eq(R.fire(fleet, seen, 7, 11).sunk, -1, "not sunk yet")
	var last := R.fire(fleet, seen, 7, 12)
	check_eq(last.sunk, 0, "the third hit sinks it")
	check_eq(seen[11], R.SUNK, "its squares show sunk")
	check(last.opened.has(13), "the water beside it opens")
	check_eq(R.afloat(fleet, seen).size(), 3, "three ships left")


func test_a_hit_fires_again_and_a_miss_passes() -> void:
	var m := _match()
	var hit := m.fire(10)
	check(hit.again, "a hit keeps the turn")
	check_eq(m.turn, 0, "still your turn")
	var miss := m.fire(15)
	check(not miss.again, "a miss passes")
	check_eq(m.turn, 1, "the CPU's turn")
	m.turn = 0
	check(not m.can_fire(10), "a square can't be fired at twice")


func test_sinking_the_fleet_wins_the_round() -> void:
	var m := _match()
	for i in 49:
		if m.fleets[1][i] != R.SEA and m.seen[0][i] == R.UNKNOWN:
			m.turn = 0
			m.fire(i)
	check_eq(m.winner, 0, "every ship sunk")
	check_eq(m.rounds_won, 1, "a round won")
	m.next_round()
	check_eq(m.round, 2, "on to round 2")
	check_eq(m.n, FleetMatch.sea_setup(2).size, "a bigger sea")


func test_losing_costs_a_heart() -> void:
	var m := _match()
	for i in 49:
		if m.fleets[0][i] != R.SEA and m.seen[1][i] == R.UNKNOWN:
			m.turn = 1
			m.fire(i)
	check_eq(m.winner, 1, "the CPU sank you")
	check_eq(m.hearts, FleetMatch.HEARTS - 1, "a heart lost")


func test_powers_sonar_and_flare() -> void:
	var m := _match()
	m.charges[0] = 2
	check_eq(m.use_sonar(7 + 3), Vector2i(3, 2), "SONAR reads the row and column")
	var opened := m.use_flare(5 * 7 + 6)
	check(not opened.is_empty(), "FLARE opens water")
	for c in opened:
		check_eq(m.fleets[1][c], R.SEA, "FLARE only opens water")
	check_eq(m.charges[0], 0, "both spent a charge")
	check_eq(m.turn, 0, "powers don't end the turn")


func test_flags_toggle_on_unknown_squares() -> void:
	var m := _match()
	check(m.toggle_flag(20), "flag a square")
	check(m.flags[0].has(20), "it's flagged")
	m.toggle_flag(20)
	check(not m.flags[0].has(20), "and unflagged")


func test_gunner_reads_numbers() -> void:
	var fleet := R.fleet_from_rows(ENEMY)
	var seen := _blank(7)
	R.fire(fleet, seen, 7, 15)
	var rng := RandomNumberGenerator.new()
	var cfg := {"read": 1.0, "blunder": 0.0}
	var shot := FleetAI.choose(seen, R.visible_numbers(fleet, seen, 7), 7, R.afloat(fleet, seen), cfg, rng)
	check([10, 11, 12].has(shot), "the numbers prove where the ship is")
	# A sharp gunner sinks a fleet in fewer turns than a sloppy one.
	var turns := [0, 0]
	for k in 2:
		var c: Dictionary = [FleetMatch.cpu_config(1), FleetMatch.cpu_config(7)][k]
		rng.seed = 11
		for g in 8:
			var f := R.place_fleet(8, [4, 3, 3, 2, 1], rng)
			var s := _blank(8)
			while not R.all_sunk(f, s):
				var i := FleetAI.choose(s, R.visible_numbers(f, s, 8), 8, R.afloat(f, s), c, rng)
				if not R.fire(f, s, 8, i).hit:
					turns[k] += 1
	check(turns[1] < turns[0], "round 7's gunner needs fewer turns (%d vs %d)" % [turns[1], turns[0]])
