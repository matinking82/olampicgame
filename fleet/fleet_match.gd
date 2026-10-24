class_name FleetMatch
extends RefCounted
## A Mine Fleet run. Both sides hide a fleet; on your turn you fire at the
## enemy sea, and a HIT lets you fire again while a miss passes the turn.
## Sinking the whole enemy fleet first wins the round. Against the CPU the
## player is Sun (side 0) and fires first; winning moves on to a bigger sea
## and a sharper gunner, losing costs a heart and replays the round, and
## the run ends when the hearts run out. Two players play first to
## MATCH_ROUNDS wins, taking turns to start.
##
## Points: every square of water opened scores a little, hits and sinkings
## a lot. Hits build a streak that multiplies points (a miss is forgiven
## once), and five in a row is Fever. Points fill a power meter that earns
## charges for SONAR (count the ship squares in a row and a column) and
## FLARE (light up the water round a square). Powers don't end the turn.

const R := preload("res://fleet/fleet_rules.gd")

const WATER_POINTS := 5
const HIT_POINTS := 100
## Per square of a ship sunk.
const SINK_POINTS := 150
const ROUND_POINTS := 1000
## Per square of your own fleet the enemy never hit.
const INTACT_POINTS := 60
const STREAK_GRACE := 1
const STREAK_STEP := 0.25
const STREAK_CAP := 3.0
const FEVER_STREAK := 5
const FEVER_MULT := 2.0
const METER_GOAL := 1200
const MAX_CHARGES := 3
const HEARTS := 3
const MATCH_ROUNDS := 2
## FLARE lights the water within this many squares of its centre.
const FLARE_REACH := 1

var n := 7
var lengths: Array = []
## Each side's own fleet, and each side's view of the other's sea.
var fleets: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var seen: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
## Squares each side has flagged on the enemy sea.
var flags: Array[Dictionary] = [{}, {}]
## SONAR readings each side has taken: square -> Vector2i(row, column).
var sonar: Array[Dictionary] = [{}, {}]
var turn := 0
var starter := 0
var vs_cpu := true
var round := 1
var hearts := HEARTS
var turns := 0
var total_turns := 0
var scores: Array[int] = [0, 0]
var round_wins: Array[int] = [0, 0]
var streak: Array[int] = [0, 0]
var quiet: Array[int] = [0, 0]
var charges: Array[int] = [0, 0]
var meter: Array[int] = [0, 0]
var winner := -1
var game_over := false
var rng := RandomNumberGenerator.new()

var rounds_won := 0
var best_streak := 0
var ships_sunk := 0
var shots := 0
var hits := 0


func _init(seed_value: int = 0, against_cpu: bool = true) -> void:
	vs_cpu = against_cpu
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func start() -> void:
	scores = [0, 0]
	round_wins = [0, 0]
	streak = [0, 0]
	quiet = [0, 0]
	charges = [0, 0]
	meter = [0, 0]
	round = 1
	hearts = HEARTS
	starter = 0
	total_turns = 0
	rounds_won = 0
	game_over = false
	start_round()


## New seas and fleets for the round.
func start_round() -> void:
	var setup := sea_setup(round if vs_cpu else 3)
	n = setup.size
	lengths = setup.ships
	set_fleets(R.place_fleet(n, lengths, rng), R.place_fleet(n, lengths, rng))
	turn = starter


## Puts two fleets out (a new round, the tutorial, tests) on clear seas.
func set_fleets(mine: PackedInt32Array, theirs: PackedInt32Array) -> void:
	fleets = [mine, theirs]
	n = roundi(sqrt(mine.size()))
	lengths = []
	for id in R.ship_count(mine):
		lengths.append(R.ship_cells(mine, id).size())
	for side in 2:
		var s := PackedInt32Array()
		s.resize(n * n)
		s.fill(R.UNKNOWN)
		seen[side] = s
		flags[side] = {}
		sonar[side] = {}
	winner = -1
	turns = 0


## The sea's size and the fleet for a round.
static func sea_setup(r: int) -> Dictionary:
	if r <= 1:
		return {"size": 7, "ships": [3, 2, 2, 1]}
	if r == 2:
		return {"size": 8, "ships": [4, 3, 2, 2]}
	if r <= 4:
		return {"size": 8, "ships": [4, 3, 3, 2, 1]}
	return {"size": 9, "ships": [5, 4, 3, 2, 2, 1]}


## How the CPU fires in a round: how much of the numbers it takes in, and
## how often it fires at random.
static func cpu_config(r: int) -> Dictionary:
	var table := [
		{"read": 0.0, "blunder": 0.5},
		{"read": 0.0, "blunder": 0.3},
		{"read": 0.0, "blunder": 0.1},
		{"read": 0.15, "blunder": 0.1},
		{"read": 0.3, "blunder": 0.05},
		{"read": 0.6, "blunder": 0.03},
		{"read": 1.0, "blunder": 0.0},
	]
	return table[mini(r, table.size()) - 1]


func is_cpu_turn() -> bool:
	return vs_cpu and turn == 1 and winner < 0


func is_running() -> bool:
	return winner < 0


## The sea the side to move fires at, and what it has seen of it.
func target_fleet() -> PackedInt32Array:
	return fleets[1 - turn]


func can_fire(i: int) -> bool:
	return is_running() and i >= 0 and i < n * n and seen[turn][i] == R.UNKNOWN


## The number a side sees on a square of the enemy sea (-1 if not water).
func number_seen(side: int, i: int) -> int:
	return R.number(fleets[1 - side], n, i) if seen[side][i] == R.WATER else -1


func afloat(side: int) -> Array:
	return R.afloat(fleets[side], seen[1 - side])


func toggle_flag(i: int) -> bool:
	if not is_running() or seen[turn][i] != R.UNKNOWN:
		return false
	if flags[turn].has(i):
		flags[turn].erase(i)
	else:
		flags[turn][i] = true
	return true


## Fires for the side to move and returns everything the view needs: hit
## or miss, a sinking, the water opened, the points, and whose turn is next.
func fire(i: int) -> Dictionary:
	if not can_fire(i):
		return {}
	var side := turn
	var shot := R.fire(fleets[1 - side], seen[side], n, i)
	flags[side].erase(i)
	for c in shot.opened:
		flags[side].erase(c)
	var base: int = WATER_POINTS * shot.opened.size()
	if shot.hit:
		base += HIT_POINTS
	if shot.sunk >= 0:
		base += SINK_POINTS * shot.sunk_cells.size()
	var result := {"side": side, "at": i, "hit": shot.hit, "sunk": shot.sunk, "sunk_cells": shot.sunk_cells,
		"opened": shot.opened, "round_over": false, "winner": -1, "round_bonus": 0, "again": shot.hit}
	if _counts(side):
		shots += 1
		if shot.hit:
			hits += 1
		if shot.sunk >= 0:
			ships_sunk += 1
	result.merge(_award(side, base, shot.hit))
	turns += 1
	if side == 0:
		total_turns += 1
	if R.all_sunk(fleets[1 - side], seen[side]):
		_win(side, result)
	elif not shot.hit:
		turn = 1 - side
	return result


func _win(side: int, result: Dictionary) -> void:
	winner = side
	var intact := 0
	for c in fleets[side].size():
		if fleets[side][c] != R.SEA and seen[1 - side][c] == R.UNKNOWN:
			intact += 1
	var bonus := ROUND_POINTS + INTACT_POINTS * intact
	result.round_over = true
	result.winner = side
	result.again = false
	result.round_bonus = bonus
	result.intact = intact
	scores[side] += bonus
	if vs_cpu:
		if side == 0:
			rounds_won += 1
		else:
			hearts -= 1
			game_over = hearts <= 0
	else:
		round_wins[side] += 1
		game_over = round_wins[side] >= MATCH_ROUNDS


## After a round: against the CPU a win moves on and a loss replays the
## round; two players alternate who starts.
func next_round() -> void:
	if vs_cpu:
		if winner == 0:
			round += 1
	else:
		round += 1
		starter = 1 - starter
	start_round()


# --- Powers ------------------------------------------------------------------------

func can_use_power() -> bool:
	return is_running() and not is_cpu_turn() and charges[turn] > 0


## SONAR: the ship squares in a square's row and column.
func use_sonar(i: int) -> Vector2i:
	if not can_use_power():
		return Vector2i(-1, -1)
	charges[turn] -= 1
	var counts := R.line_counts(fleets[1 - turn], n, i)
	sonar[turn][i] = counts
	return counts


## FLARE: opens every water square within FLARE_REACH of a square, and
## spreads on through calm water. Returns the squares opened.
func use_flare(i: int) -> PackedInt32Array:
	if not can_use_power():
		return PackedInt32Array()
	charges[turn] -= 1
	var start := []
	var x := i % n
	var y := i / n
	for dy in range(-FLARE_REACH, FLARE_REACH + 1):
		for dx in range(-FLARE_REACH, FLARE_REACH + 1):
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and ny >= 0 and nx < n and ny < n:
				start.append(ny * n + nx)
	var opened := R.open_water(fleets[1 - turn], seen[turn], n, start)
	for c in opened:
		flags[turn].erase(c)
	return opened


# --- Points --------------------------------------------------------------------------

func streak_mult(side: int) -> float:
	var m := minf(1.0 + STREAK_STEP * (streak[side] - 1), STREAK_CAP) if streak[side] > 0 else 1.0
	return m * (FEVER_MULT if is_fever(side) else 1.0)


func is_fever(side: int) -> bool:
	return streak[side] >= FEVER_STREAK


func meter_fill(side: int) -> float:
	return float(meter[side]) / METER_GOAL


func _award(side: int, base: int, combo: bool) -> Dictionary:
	if combo:
		streak[side] += 1
		quiet[side] = 0
	else:
		quiet[side] += 1
		if quiet[side] > STREAK_GRACE:
			streak[side] = 0
	if _counts(side):
		best_streak = maxi(best_streak, streak[side])
	var mult := streak_mult(side) if combo else 1.0
	var points := roundi(base * mult)
	scores[side] += points
	var earned := 0
	meter[side] += points
	while meter[side] >= METER_GOAL:
		meter[side] -= METER_GOAL
		if charges[side] < MAX_CHARGES:
			charges[side] += 1
			earned += 1
	return {"points": points, "base": base, "mult": mult, "streak": streak[side],
		"fever": is_fever(side), "combo": combo, "charges_earned": earned}


func _counts(side: int) -> bool:
	return side == 0 or not vs_cpu
