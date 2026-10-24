class_name DiceMatch
extends RefCounted
## One game of Tic Tac Roll: the board, the dice, whose turn it is, scoring,
## streaks, the two powers, hearts and the CPU gauntlet. No nodes, so the
## tests, the CPU and the balancing sim can drive it directly.
##
## A turn: roll the five dice up to three times, holding any between rolls,
## then claim a cell the dice fit (or pass when nothing fits after the last
## roll). Three cells in a row wins the round. Against the CPU the player is
## side 0 and always starts; losing a round costs a heart and replays it, and
## the run ends when the hearts run out. Two players play first to
## MATCH_ROUNDS round wins.

const R := preload("res://dice/dice_rules.gd")

## Claim points are the dice score times this.
const CLAIM_MULT := 10
const STEAL_POINTS := 150
## Extra for filling a 5 of a Kind cell.
const JACKPOT_POINTS := 500
const ROUND_POINTS := 1000
## Per empty cell left when the round is won: quick wins pay more.
const EMPTY_POINTS := 60
## The streak counts "combo" claims (anything but Chance or a bare pair of a
## face), and steals; it survives this many quiet turns.
const STREAK_GRACE := 1
const STREAK_STEP := 0.25
const STREAK_CAP := 3.0
const FEVER_STREAK := 5
const FEVER_MULT := 2.0
## Every this many points earns a power charge (+1 Roll or Nudge).
const METER_GOAL := 1200
const MAX_CHARGES := 3
const HEARTS := 3
const MATCH_ROUNDS := 3
## After this many turns (both sides) the round is decided on cells owned.
const MAX_TURNS := 40

var cats := PackedInt32Array()
var owners := PackedInt32Array()
## The score each owned cell was claimed with.
var marks := PackedInt32Array()
var dice := PackedInt32Array([1, 2, 3, 4, 5])
var held: Array[bool] = [false, false, false, false, false]
var rolls_left := R.ROLLS
## False until the first roll of a turn; nothing can be claimed before it.
var rolled := false
var turn := 0
var starter := 0
var vs_cpu := true
var round := 1
var hearts := HEARTS
## Turns this round (both sides), and the player's turns over the run.
var turns := 0
var total_turns := 0
var scores: Array[int] = [0, 0]
var round_points: Array[int] = [0, 0]
var round_wins: Array[int] = [0, 0]
var streak: Array[int] = [0, 0]
var quiet: Array[int] = [0, 0]
var charges: Array[int] = [0, 0]
var meter: Array[int] = [0, 0]
## -1 while the round runs, otherwise the side that won it.
var winner := -1
var draw := false
## True when the round ended on a full board (or the turn limit), not a line.
var full_board := false
var game_over := false
var rng := RandomNumberGenerator.new()
## Dice values the next rolls must produce, in order (the tutorial's script).
var rigged: Array[int] = []

var rounds_won := 0
var best_streak := 0
var jackpots := 0
var steals := 0
var best_claim := 0


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


## A freshly dealt board. From round 4 the CPU starts with cells of its own.
func start_round() -> void:
	var deck: Array = R.DECK.duplicate()
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: int = deck[i]
		deck[i] = deck[j]
		deck[j] = t
	cats = PackedInt32Array(deck)
	owners = PackedInt32Array()
	owners.resize(R.CELLS)
	owners.fill(R.NONE)
	marks = PackedInt32Array()
	marks.resize(R.CELLS)
	winner = -1
	draw = false
	full_board = false
	turns = 0
	round_points = [0, 0]
	turn = starter
	_new_turn()
	if vs_cpu:
		for k in cpu_config(round).head_start:
			_head_start()


## How the CPU plays in a round: how many futures it imagines per choice of
## dice to hold, how much it fumbles, how well it spots your threats, and
## how many cells it starts with.
static func cpu_config(r: int) -> Dictionary:
	return {
		"samples": mini(4 + 6 * (r - 1), 40),
		"noise": [8.0, 5.0, 3.0, 2.0, 1.2][r - 1] if r <= 5 else 0.6,
		"block": [0.2, 0.4, 0.65, 0.85][r - 1] if r <= 4 else 1.0,
		"head_start": 0 if r < 4 else (1 if r < 7 else (2 if r < 10 else 3)),
	}


func is_cpu_turn() -> bool:
	return vs_cpu and turn == 1 and winner < 0 and not draw


func can_roll() -> bool:
	return winner < 0 and not draw and rolls_left > 0


## Rolls every die that isn't held. Returns which dice moved, and whether
## the roll came up five of a kind.
func roll() -> Dictionary:
	if not can_roll():
		return {}
	var moved := PackedInt32Array()
	for d in R.DICE:
		if held[d] and rolled:
			continue
		dice[d] = rigged.pop_front() if not rigged.is_empty() else rng.randi_range(1, 6)
		moved.append(d)
	if not rolled:
		held = [false, false, false, false, false]
	rolled = true
	rolls_left -= 1
	var jackpot := R.is_five_kind(dice) and moved.size() > 0
	return {"side": turn, "moved": moved, "dice": dice.duplicate(), "jackpot": jackpot,
		"options": options(), "rolls_left": rolls_left}


func toggle_hold(d: int) -> bool:
	if not rolled or winner >= 0 or draw or d < 0 or d >= R.DICE:
		return false
	held[d] = not held[d]
	return true


## Cells the side to move can claim with its dice right now.
func options() -> PackedInt32Array:
	if not rolled or winner >= 0 or draw:
		return PackedInt32Array()
	return R.claimable(cats, owners, marks, turn, dice)


func can_claim(i: int) -> bool:
	return options().has(i)


## Nothing fits and no rolls are left: the turn can only be passed.
func is_bust() -> bool:
	return rolled and rolls_left == 0 and options().is_empty() and winner < 0 and not draw


## Claims a cell for the side to move and returns everything the view needs
## to animate it. Empty if the claim isn't allowed.
func claim(i: int) -> Dictionary:
	if not can_claim(i):
		return {}
	var side := turn
	var cat := cats[i]
	var value := R.score(cat, dice)
	var stolen := owners[i] == 1 - side
	var result := {
		"side": side, "at": i, "cat": cat, "value": value, "stolen": stolen,
		"prev_owner": owners[i], "prev_mark": marks[i], "bust": false,
		"line": PackedInt32Array(), "full": false, "round_bonus": 0, "jackpot": cat == R.Cat.FIVE_KIND,
	}
	owners[i] = side
	marks[i] = value
	var base := value * CLAIM_MULT
	if stolen:
		base += STEAL_POINTS
	if cat == R.Cat.FIVE_KIND:
		base += JACKPOT_POINTS
	var combo := stolen or not (cat == R.Cat.CHANCE or (R.is_upper(cat) and value < (cat + 1) * 3))
	if _counts(side):
		best_claim = maxi(best_claim, value)
		if stolen:
			steals += 1
		if cat == R.Cat.FIVE_KIND:
			jackpots += 1
	result.merge(_award(side, base, combo))
	_end_turn(result)
	return result


## Gives up the turn when nothing fits after the last roll.
func pass_turn() -> Dictionary:
	if not is_bust():
		return {}
	var result := {"side": turn, "at": -1, "bust": true, "stolen": false, "line": PackedInt32Array(),
		"full": false, "round_bonus": 0, "jackpot": false}
	result.merge(_award(turn, 0, false))
	_end_turn(result)
	return result


# --- Powers ------------------------------------------------------------------------

## +1 Roll: one more roll this turn.
func can_extra_roll() -> bool:
	return winner < 0 and not draw and charges[turn] > 0


func extra_roll() -> bool:
	if not can_extra_roll():
		return false
	charges[turn] -= 1
	rolls_left += 1
	return true


## Nudge: turns one die up a pip (a 6 wraps round to 1).
func can_nudge() -> bool:
	return rolled and winner < 0 and not draw and charges[turn] > 0


func nudge(d: int) -> bool:
	if not can_nudge() or d < 0 or d >= R.DICE:
		return false
	charges[turn] -= 1
	dice[d] = dice[d] % 6 + 1
	return true


# --- Rounds ------------------------------------------------------------------------

## After a round: against the CPU a win moves on to the next round and a
## loss replays it; two players alternate who starts.
func next_round() -> void:
	if vs_cpu:
		if winner == 0:
			round += 1
	else:
		round += 1
		starter = 1 - starter
	start_round()


func streak_mult(side: int) -> float:
	var m := minf(1.0 + STREAK_STEP * (streak[side] - 1), STREAK_CAP) if streak[side] > 0 else 1.0
	return m * (FEVER_MULT if is_fever(side) else 1.0)


func is_fever(side: int) -> bool:
	return streak[side] >= FEVER_STREAK


## Applies the streak, Fever and the power meter to a turn's base points.
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
	round_points[side] += points
	var earned := 0
	meter[side] += points
	while meter[side] >= METER_GOAL:
		meter[side] -= METER_GOAL
		if charges[side] < MAX_CHARGES:
			charges[side] += 1
			earned += 1
	return {"points": points, "base": base, "mult": mult, "streak": streak[side],
		"fever": is_fever(side), "combo": combo, "charges_earned": earned}


## Settles a line, a full board or the turn limit, else hands the turn over.
func _end_turn(result: Dictionary) -> void:
	var side: int = result.side
	turns += 1
	if side == 0:
		total_turns += 1
	var line := R.winning_line(owners, side)
	if not line.is_empty():
		result.line = line
		_win(side, result)
		return
	if R.is_full(owners) or turns >= MAX_TURNS:
		result.full = true
		full_board = true
		var lead := R.count_owned(owners, 0) - R.count_owned(owners, 1)
		if lead == 0:
			lead = round_points[0] - round_points[1]
		if lead == 0:
			draw = true
		else:
			_win(0 if lead > 0 else 1, result)
		return
	turn = 1 - side
	_new_turn()


func _win(side: int, result: Dictionary) -> void:
	winner = side
	if not vs_cpu:
		round_wins[side] += 1
		game_over = round_wins[side] >= MATCH_ROUNDS
		return
	if side == 0:
		rounds_won += 1
		var empty := R.CELLS - R.count_owned(owners, 0) - R.count_owned(owners, 1)
		var bonus := (ROUND_POINTS + EMPTY_POINTS * empty) * round
		if result.full:
			bonus /= 2
		scores[0] += bonus
		result.round_bonus = bonus
	else:
		hearts -= 1
		game_over = hearts <= 0


func _new_turn() -> void:
	held = [false, false, false, false, false]
	rolls_left = R.ROLLS
	rolled = false


## Whether this side's deeds count toward the run's stats.
func _counts(side: int) -> bool:
	return side == 0 or not vs_cpu


## The CPU's head start: an easy cell, claimed with a plausible score.
func _head_start() -> void:
	var easy: Array[int] = []
	for i in R.CELLS:
		if owners[i] == R.NONE and (R.is_upper(cats[i]) or cats[i] == R.Cat.CHANCE):
			easy.append(i)
	if easy.is_empty():
		return
	var at: int = easy[rng.randi() % easy.size()]
	for attempt in 200:
		var d := PackedInt32Array()
		for k in R.DICE:
			d.append(rng.randi_range(1, 6))
		var s := R.score(cats[at], d)
		if s >= 0:
			owners[at] = 1
			marks[at] = s
			return
