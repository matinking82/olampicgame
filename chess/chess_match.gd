class_name ChessMatch
extends RefCounted
## One game of Merge Mate: the board, whose turn it is, spawning, scoring,
## streaks, the Upgrade power and the CPU gauntlet. No nodes, so the tests
## and the CPU can drive it directly.
##
## Against the CPU the player is side 0 and the run is a gauntlet: checkmate
## the CPU to clear the round, and the next CPU is sharper and spawns more.
## The run ends when the player's king is mated. Two players share one
## screen and play a single match.

const R := preload("res://chess/chess_rules.gd")

## Points for the action itself, before the streak multiplier.
const CAPTURE_POINTS := [0, 40, 120, 120, 200, 360, 480, 0]
## Points for creating a piece of this tier by merging.
const MERGE_POINTS := [0, 0, 30, 80, 200, 500]
const PROMOTE_POINTS := 300
const CHECK_POINTS := 100
const ROUND_POINTS := 1500
## Clearing a round in fewer of your own moves than this pays a speed bonus.
const FAST_MOVES := 40
const FAST_POINTS := 40
## The streak counts scoring turns; it survives quiet turns up to the grace.
const STREAK_GRACE := 2
const STREAK_STEP := 0.25
const STREAK_CAP := 3.0
const FEVER_STREAK := 5
const FEVER_MULT := 2.0
## Every this many points earns an Upgrade charge (tap one of your pieces to
## raise it a tier, without spending the turn).
const METER_GOAL := 1500
const MAX_CHARGES := 3
## Against the CPU a round lasts at most this many of the player's moves;
## then material decides it (ties go to the player).
const ROUND_MOVES := 50
## Two players with this many actions and no mate draw.
const MAX_PLIES := 300

var cells := PackedInt32Array()
var turn := 0
var vs_cpu := true
var round := 1
## Actions this round (both sides).
var plies := 0
## The player's own actions this round and over the whole run.
var round_moves := 0
var total_moves := 0
var scores: Array[int] = [0, 0]
var streak: Array[int] = [0, 0]
var quiet: Array[int] = [0, 0]
var charges: Array[int] = [0, 0]
var meter: Array[int] = [0, 0]
var spawn_chance: Array[float] = [0.85, 0.85]
var minor_chance: Array[float] = [0.2, 0.2]
## -1 while the round runs, otherwise the side that delivered mate.
var winner := -1
var draw := false
var game_over := false
var last_from := -1
var last_to := -1
var rng := RandomNumberGenerator.new()

var best_streak := 0
var total_captures := 0
var total_merges := 0
var best_tier := 1
var rounds_won := 0


func _init(seed_value: int = 0, against_cpu: bool = true) -> void:
	vs_cpu = against_cpu
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func start() -> void:
	scores = [0, 0]
	streak = [0, 0]
	quiet = [0, 0]
	charges = [0, 0]
	meter = [0, 0]
	round = 1
	total_moves = 0
	rounds_won = 0
	game_over = false
	start_round()


## A fresh board for the current round: each king with three pawns, and
## from round 3 the CPU brings extra pieces.
func start_round() -> void:
	cells = PackedInt32Array()
	cells.resize(R.CELLS)
	for side in 2:
		var back := 7 if side == 0 else 0
		var front := back + R.forward(side)
		cells[R.idx(4, back)] = R.piece(R.KING, side)
		for x in [3, 4, 5]:
			cells[R.idx(x, front)] = R.piece(R.PAWN, side)
	turn = 0
	plies = 0
	round_moves = 0
	winner = -1
	draw = false
	last_from = -1
	last_to = -1
	streak = [0, 0]
	quiet = [0, 0]
	if vs_cpu:
		var cfg := cpu_config(round)
		spawn_chance = [0.85, cfg.spawn]
		minor_chance = [0.2, cfg.minor]
		for type: int in cfg.extra:
			_spawn(1, type)
	else:
		spawn_chance = [0.85, 0.85]
		minor_chance = [0.2, 0.2]


## How the CPU plays in a round: search depth, how much it fumbles (random
## slack in its scores), its spawn odds and the pieces it starts with.
static func cpu_config(r: int) -> Dictionary:
	var extra: Array[int] = []
	if r >= 3:
		extra.append(R.PAWN)
	if r >= 4:
		extra.append(R.KNIGHT)
	if r >= 5:
		extra.append_array([R.BISHOP, R.PAWN])
	if r >= 6:
		extra.append(R.ROOK)
	for i in maxi(0, r - 6) * 2:
		extra.append(R.PAWN)
	return {
		"depth": 1 if r <= 2 else 2,
		"noise": [250.0, 120.0, 80.0, 30.0][r - 1] if r <= 4 else 0.0,
		"spawn": minf(1.0, 0.65 + 0.08 * (r - 1)),
		"minor": minf(0.45, 0.15 + 0.05 * (r - 1)),
		"extra": extra,
	}


func is_cpu_turn() -> bool:
	return vs_cpu and turn == 1 and winner < 0 and not draw


func targets(from: int) -> PackedInt32Array:
	if from < 0 or from >= R.CELLS or cells[from] == R.EMPTY or R.side_of(cells[from]) != turn:
		return PackedInt32Array()
	return R.legal_targets(cells, from)


func can_act(from: int, to: int) -> bool:
	return winner < 0 and not draw and targets(from).has(to)


func in_check(side: int) -> bool:
	return R.in_check(cells, side)


## Plays one action for the side to move and returns everything the view
## needs to animate it. Empty if the action isn't allowed.
func act(from: int, to: int) -> Dictionary:
	if not can_act(from, to):
		return {}
	var side := turn
	var p := cells[from]
	var target := cells[to]
	var kind := "move"
	var merge_type := 0
	if R.can_merge(p, target):
		kind = "merge"
		merge_type = R.merged_type(R.type_of(p), rng.randf())
	elif target != R.EMPTY:
		kind = "capture"
	cells = R.apply(cells, from, to, merge_type)
	var result_piece := cells[to]
	var promoted := kind != "merge" and R.type_of(p) == R.PAWN and R.type_of(result_piece) == R.QUEEN

	var base := 0
	if kind == "capture":
		base += CAPTURE_POINTS[R.type_of(target)]
		if side == 0 or not vs_cpu:
			total_captures += 1
	elif kind == "merge":
		var tier: int = R.TIER[R.type_of(result_piece)]
		base += MERGE_POINTS[tier]
		if side == 0 or not vs_cpu:
			total_merges += 1
			best_tier = maxi(best_tier, tier)
	if promoted:
		base += PROMOTE_POINTS
	last_from = from
	last_to = to
	plies += 1
	if side == 0:
		round_moves += 1
		total_moves += 1

	var spawn := -1
	if rng.randf() < spawn_chance[side]:
		spawn = _spawn(side, R.PAWN if rng.randf() >= minor_chance[side] else (R.KNIGHT if rng.randf() < 0.5 else R.BISHOP))
	var check := R.in_check(cells, 1 - side)
	if check:
		base += CHECK_POINTS
	var award := _award(side, base)
	var result := {
		"side": side, "from": from, "to": to, "kind": kind, "piece": p, "target": target,
		"result": result_piece, "promoted": promoted, "check": check,
		"spawn": spawn, "spawn_piece": cells[spawn] if spawn >= 0 else 0,
		"mate": false, "draw": false, "passed": false, "round_bonus": 0, "timeout": false,
	}
	result.merge(award)
	_next_turn(result)
	return result


## Spends an Upgrade charge on one of the mover's pieces: it rises a tier
## (a pawn becomes a knight or bishop). Doesn't use up the turn.
func can_upgrade(at: int) -> bool:
	if winner >= 0 or draw or charges[turn] <= 0 or at < 0 or at >= R.CELLS:
		return false
	var p := cells[at]
	if p == R.EMPTY or R.side_of(p) != turn:
		return false
	var t: int = R.TIER[R.type_of(p)]
	return t > 0 and t < R.MAX_TIER


func upgrade(at: int) -> Dictionary:
	if not can_upgrade(at):
		return {}
	var side := turn
	var before := cells[at]
	charges[side] -= 1
	cells[at] = R.piece(R.merged_type(R.type_of(before), rng.randf()), side)
	var check := R.in_check(cells, 1 - side)
	best_tier = maxi(best_tier, R.TIER[R.type_of(cells[at])])
	var result := {"side": side, "at": at, "piece": before, "result": cells[at], "check": check,
		"mate": false, "draw": false, "passed": false, "round_bonus": 0, "timeout": false}
	# An upgrade can deliver mate on its own.
	if check and not R.has_legal_move(cells, 1 - side):
		_win(side, result)
	return result


## Moves on after a round is won: next round, harder CPU, scores kept.
func next_round() -> void:
	round += 1
	start_round()


func streak_mult(side: int) -> float:
	var m := minf(1.0 + STREAK_STEP * (streak[side] - 1), STREAK_CAP) if streak[side] > 0 else 1.0
	return m * (FEVER_MULT if is_fever(side) else 1.0)


func is_fever(side: int) -> bool:
	return streak[side] >= FEVER_STREAK


## Applies streak, fever and the Upgrade meter to an action's base points.
func _award(side: int, base: int) -> Dictionary:
	if base > 0:
		streak[side] += 1
		quiet[side] = 0
	else:
		quiet[side] += 1
		if quiet[side] > STREAK_GRACE:
			streak[side] = 0
	if side == 0 or not vs_cpu:
		best_streak = maxi(best_streak, streak[side])
	var mult := streak_mult(side) if base > 0 else 1.0
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
		"fever": is_fever(side), "charges_earned": earned}


## Hands the turn over and settles mate, stalemate passes and draws.
func _next_turn(result: Dictionary) -> void:
	var side: int = result.side
	var other := 1 - side
	if R.has_legal_move(cells, other):
		turn = other
	elif R.in_check(cells, other):
		_win(side, result)
		return
	elif R.has_legal_move(cells, side):
		# Boxed in but not in check: they pass and the mover goes again.
		result.passed = true
		turn = side
	else:
		_draw(result)
		return
	if vs_cpu and plies >= ROUND_MOVES * 2:
		result.timeout = true
		var lead := material(0) - material(1)
		result.material_lead = lead
		_win(0 if lead >= 0 else 1, result)
	elif plies >= MAX_PLIES:
		_draw(result)


func _win(side: int, result: Dictionary) -> void:
	winner = side
	result.mate = not result.get("timeout", false)
	if not vs_cpu:
		game_over = true
		return
	if side == 0:
		rounds_won += 1
		var bonus := ROUND_POINTS * round
		if result.mate:
			bonus += maxi(0, FAST_MOVES - round_moves) * FAST_POINTS * round
		else:
			bonus /= 2
		scores[0] += bonus
		result.round_bonus = bonus
	else:
		game_over = true


## A drawn round is replayed (against the CPU) or ends the match (two players).
func _draw(result: Dictionary) -> void:
	draw = true
	result.draw = true
	if not vs_cpu:
		game_over = true


## Drops a new piece on a random empty square of the side's home rows.
## Returns the square, or -1 when the rows are full.
func _spawn(side: int, type: int) -> int:
	var free: Array[int] = []
	for y in R.home_rows(side):
		for x in R.SIZE:
			if cells[R.idx(x, y)] == R.EMPTY:
				free.append(R.idx(x, y))
	if free.is_empty():
		return -1
	var at: int = free[rng.randi() % free.size()]
	cells[at] = R.piece(type, side)
	return at


## Total piece value a side has on the board (the CPU's values).
func material(side: int) -> int:
	var total := 0
	for p in cells:
		if p != R.EMPTY and R.side_of(p) == side:
			total += ChessAI.VALUE[R.type_of(p)]
	return total


func moves_left() -> int:
	return maxi(0, ROUND_MOVES - round_moves)


func piece_count(side: int) -> int:
	var n := 0
	for p in cells:
		if p != R.EMPTY and R.side_of(p) == side:
			n += 1
	return n
