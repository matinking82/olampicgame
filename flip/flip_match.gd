class_name FlipMatch
extends RefCounted
## A Flip Four run. Against the CPU the player is Sun (side 0) and moves
## first. A round ends when every column is full, and the most discs wins
## it (locked or not). Winning moves on to a harder
## round: a sharper CPU, candy blocks in the board from round 3, and a
## bigger board from round 5. Losing costs a heart and replays the round,
## a tie just replays it, and the run ends when the hearts run out. Two
## players play first to MATCH_ROUNDS wins, taking turns to start.
##
## Points: every drop scores, every disc it flips scores more, and every
## disc it locks more still. Moves that flip COMBO_FLIPS or more, or lock
## a line, build a streak that multiplies points, and five in a row is
## Fever. Points also fill a power meter that earns
## charges for HINT and UNDO.

const R := preload("res://flip/flip_rules.gd")

const DROP_POINTS := 10
const FLIP_POINTS := 25
## Per disc newly locked by a line.
const LOCK_POINTS := 40
## A move making two lines at once (or a run of five or more).
const DOUBLE_POINTS := 300
## A move flipping this many discs is a combo.
const COMBO_FLIPS := 2
## Winning a round: a base, plus per disc of the margin.
const ROUND_POINTS := 1000
const MARGIN_POINTS := 40
const STREAK_GRACE := 1
const STREAK_STEP := 0.25
const STREAK_CAP := 3.0
const FEVER_STREAK := 5
const FEVER_MULT := 2.0
const METER_GOAL := 1000
const MAX_CHARGES := 3
const HEARTS := 3
const MATCH_ROUNDS := 2
## How hard a HINT thinks.
const HINT_CONFIG := {"depth": 4, "noise": 0.0, "endgame": 8}

var board := PackedInt32Array()
var w := 7
var h := 6
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
## -1 while the round runs, else the side that won it.
var winner := -1
var draw := false
var game_over := false
var rng := RandomNumberGenerator.new()
## Positions before each of the player's moves this round, for UNDO.
var _history: Array[Dictionary] = []

var rounds_won := 0
var best_streak := 0
var best_flip := 0
var total_flips := 0
var lines_locked := 0


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


## A fresh board for the round.
func start_round() -> void:
	var shape := board_shape(round) if vs_cpu else Vector2i(7, 6)
	var pairs := block_pairs(round) if vs_cpu else 0
	set_board(R.new_board(shape.x, shape.y, R.make_blocks(shape.x, shape.y, pairs, rng)), shape.x)
	turn = starter


## Replaces the board (a new round, the tutorial, tests) and readies the
## lookups the CPU's thread will read.
func set_board(b: PackedInt32Array, width: int) -> void:
	board = b
	w = width
	h = b.size() / width
	R.rays(w, h)
	R.windows(w, h)
	winner = -1
	draw = false
	turns = 0
	_history.clear()


static func board_shape(r: int) -> Vector2i:
	return Vector2i(7, 6) if r < 5 else Vector2i(8, 7)


static func block_pairs(r: int) -> int:
	return 0 if r < 3 else (1 if r < 5 else (2 if r < 8 else 3))


## How the CPU plays in a round: how deep it looks, how much it fumbles,
## and from how many empty cells it searches to the end.
static func cpu_config(r: int) -> Dictionary:
	var table := [
		{"depth": 1, "noise": 30.0, "endgame": 0},
		{"depth": 2, "noise": 14.0, "endgame": 0},
		{"depth": 3, "noise": 6.0, "endgame": 6},
		{"depth": 4, "noise": 2.0, "endgame": 8},
		{"depth": 4, "noise": 0.0, "endgame": 8},
		{"depth": 4, "noise": 0.0, "endgame": 9},
		{"depth": 5, "noise": 0.0, "endgame": 9},
	]
	return table[mini(r, table.size()) - 1]


func is_cpu_turn() -> bool:
	return vs_cpu and turn == 1 and winner < 0 and not draw


func is_running() -> bool:
	return winner < 0 and not draw


func can_drop(col: int) -> bool:
	return is_running() and R.can_drop(board, w, col)


func columns() -> PackedInt32Array:
	return R.moves(board, w) if is_running() else PackedInt32Array()


func count(side: int) -> int:
	return R.count(board, side)


## Where a drop would land and what it would flip and lock, without playing it.
func preview(col: int) -> Dictionary:
	var b := board.duplicate()
	return R.drop(b, w, h, col, turn)


## Drops a disc for the side to move and returns everything the view needs:
## where it landed, the flips and locks, the points, and how the round
## ended if it did.
func drop(col: int) -> Dictionary:
	if not can_drop(col):
		return {}
	var side := turn
	if side == 0 and vs_cpu:
		_history.append(_snapshot())
	var made := R.drop(board, w, h, col, side)
	var flipped: PackedInt32Array = made.flipped
	var locked: PackedInt32Array = made.locked
	var runs: Array = made.runs
	var longest := 0
	for run: PackedInt32Array in runs:
		longest = maxi(longest, run.size())
	var double := runs.size() > 1 or longest > R.LINE
	var base := DROP_POINTS + FLIP_POINTS * flipped.size() + LOCK_POINTS * locked.size()
	if double:
		base += DOUBLE_POINTS
	var combo := flipped.size() >= COMBO_FLIPS or not runs.is_empty()
	var result := {"side": side, "col": col, "at": made.at, "flipped": flipped, "locked": locked,
		"runs": runs, "double": double, "round_over": false, "winner": -1, "draw": false, "round_bonus": 0}
	if _counts(side):
		best_flip = maxi(best_flip, flipped.size())
		total_flips += flipped.size()
		lines_locked += runs.size()
	result.merge(_award(side, base, combo))
	_end_turn(result)
	return result


## A full board ends the round on discs. Else the turn passes.
func _end_turn(result: Dictionary) -> void:
	var side: int = result.side
	turns += 1
	if side == 0:
		total_turns += 1
	if not R.is_full(board, w):
		turn = 1 - side
		return
	result.counts = [count(0), count(1)]
	var lead := R.leader(board)
	if lead < 0:
		draw = true
		result.round_over = true
		result.draw = true
		if not vs_cpu:
			starter = 1 - starter
		return
	_win(lead, ROUND_POINTS + MARGIN_POINTS * absi(count(0) - count(1)), result)


func _win(side: int, bonus: int, result: Dictionary) -> void:
	winner = side
	result.round_over = true
	result.winner = side
	result.round_bonus = bonus
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


## After a round: against the CPU a win moves on and anything else replays
## the round; two players alternate who starts.
func next_round() -> void:
	if vs_cpu:
		if winner == 0:
			round += 1
	else:
		round += 1
		if not draw:
			starter = 1 - starter
	start_round()


# --- Powers ------------------------------------------------------------------------

func can_hint() -> bool:
	return is_running() and not is_cpu_turn() and charges[turn] > 0


## Spends a charge on a hint; the game then asks the CPU's brain (at
## HINT_CONFIG strength) for the move, off the main thread.
func spend_hint() -> bool:
	if not can_hint():
		return false
	charges[turn] -= 1
	return true


## UNDO takes back the player's last move and the CPU's answer (vs CPU only).
func can_undo() -> bool:
	return vs_cpu and is_running() and turn == 0 and not _history.is_empty() and charges[0] > 0


func undo() -> bool:
	if not can_undo():
		return false
	var s: Dictionary = _history.pop_back()
	var left := maxi(mini(charges[0], s.charges[0]) - 1, 0)
	board = s.board
	turn = s.turn
	turns = s.turns
	total_turns = s.total_turns
	scores.assign(s.scores)
	streak.assign(s.streak)
	quiet.assign(s.quiet)
	meter.assign(s.meter)
	charges.assign(s.charges)
	charges[0] = left
	return true


func _snapshot() -> Dictionary:
	return {"board": board.duplicate(), "turn": turn, "turns": turns, "total_turns": total_turns,
		"scores": scores.duplicate(), "streak": streak.duplicate(), "quiet": quiet.duplicate(),
		"meter": meter.duplicate(), "charges": charges.duplicate()}


# --- Points --------------------------------------------------------------------------

func streak_mult(side: int) -> float:
	var m := minf(1.0 + STREAK_STEP * (streak[side] - 1), STREAK_CAP) if streak[side] > 0 else 1.0
	return m * (FEVER_MULT if is_fever(side) else 1.0)


func is_fever(side: int) -> bool:
	return streak[side] >= FEVER_STREAK


func meter_fill(side: int) -> float:
	return float(meter[side]) / METER_GOAL


## Applies the streak, Fever and the power meter to a move's base points.
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


## Whether a side's moves count toward the run's stats (the player's do).
func _counts(side: int) -> bool:
	return side == 0 or not vs_cpu
