class_name DiceAI
extends RefCounted
## The CPU for Tic Tac Roll. Each cell gets a worth for the side to move
## (winning, blocking the other side's lines, building its own lines) plus
## the points the dice would score there. To decide which dice to hold it
## imagines a handful of rerolls for every choice of dice to keep and takes
## the choice with the best average, or claims now when that's better.
##
## `cfg` is DiceMatch.cpu_config(): samples (rerolls imagined per choice),
## noise (fumbling) and block (the chance it spots each threat of yours).

const R := preload("res://dice/dice_rules.gd")
const WIN := 10000.0
const BLOCK := 900.0
## Worth per point the claim scores (a 250-point claim is worth 3).
const POINT_WEIGHT := 0.012
## Unstealable cells, and stealable ones claimed with a high score, are safer.
const SAFETY := 2.0
const BUST := -8.0
## The best a stealable category can score, for judging how safe a claim is.
const CAT_MAX := [5, 10, 15, 20, 25, 30, 30, 30, 30, 30, 25, 30, 40, 50]


## What to do with the dice now: {"claim": cell}, {"pass": true} when
## nothing fits and no rolls are left, or {"hold": [bool x5]} to roll again.
static func decide(cats: PackedInt32Array, owners: PackedInt32Array, marks: PackedInt32Array, side: int,
		dice: PackedInt32Array, rolls_left: int, cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var pos := position_values(cats, owners, side, cfg.block, cfg.noise, rng)
	var now := _best(cats, owners, marks, side, dice, pos)
	if rolls_left <= 0:
		return {"claim": now.cell} if now.cell >= 0 else {"pass": true}
	if now.cell >= 0 and now.value >= WIN * 0.5:
		return {"claim": now.cell}
	var best_mask := -1
	var best_avg := -INF
	var trial := PackedInt32Array(dice)
	# A miss still leaves rolls when more than this one remain.
	var miss := BUST if rolls_left == 1 else BUST * 0.3
	for mask in 1 << R.DICE:
		if mask == (1 << R.DICE) - 1:
			continue
		var total := 0.0
		for s in cfg.samples:
			for d in R.DICE:
				trial[d] = dice[d] if mask & (1 << d) else rng.randi_range(1, 6)
			var got := _best(cats, owners, marks, side, trial, pos)
			total += got.value if got.cell >= 0 else miss
		var avg: float = total / cfg.samples
		if avg > best_avg:
			best_avg = avg
			best_mask = mask
	# Rolls after this one are worth a little extra.
	best_avg += (rolls_left - 1) * 0.5
	if now.cell >= 0 and now.value >= best_avg:
		return {"claim": now.cell}
	var hold: Array[bool] = []
	for d in R.DICE:
		hold.append(best_mask & (1 << d) != 0)
	return {"hold": hold}


## How much owning each cell is worth to `side` apart from the dice points.
## Each of the other side's threats is spotted with chance `block`.
static func position_values(cats: PackedInt32Array, owners: PackedInt32Array, side: int, block: float,
		noise: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var other := 1 - side
	var pos := PackedFloat32Array()
	pos.resize(R.CELLS)
	for line in R.lines():
		var own := 0
		var opp := 0
		for c in line:
			if owners[c] == side:
				own += 1
			elif owners[c] == other:
				opp += 1
		if opp == 0:
			# Building: the empty cells of a line only we are in.
			for c in line:
				if owners[c] == R.NONE:
					pos[c] += WIN if own == R.LINE - 1 else pow(5.0, own)
		elif opp == 1 and own > 0:
			# Stealing their only cell here turns the line ours.
			for c in line:
				if owners[c] == other:
					pos[c] += WIN if own == R.LINE - 1 else pow(5.0, own)
		if own == 0 and opp > 0 and rng.randf() < block:
			# Their line: claiming any cell of it (or stealing one) spoils it.
			var w := BLOCK if opp == R.LINE - 1 else 2.0 * opp
			for c in line:
				pos[c] += w
	for i in R.CELLS:
		if R.FIXED.has(cats[i]):
			pos[i] += SAFETY
		if noise > 0.0:
			pos[i] += rng.randfn(0.0, noise)
	return pos


## The best claim for these dice: {"cell": i or -1, "value": worth}.
static func _best(cats: PackedInt32Array, owners: PackedInt32Array, marks: PackedInt32Array, side: int,
		dice: PackedInt32Array, pos: PackedFloat32Array) -> Dictionary:
	var c := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	var total := 0
	for d in dice:
		c[d] += 1
		total += d
	var best_cell := -1
	var best_value := -INF
	for i in R.CELLS:
		if owners[i] == side:
			continue
		var s := R.score_counts(cats[i], c, total)
		if s < 0 or (owners[i] != R.NONE and s <= marks[i]):
			continue
		var points := s * DiceMatch.CLAIM_MULT
		if owners[i] != R.NONE:
			points += DiceMatch.STEAL_POINTS
		var v := pos[i] + points * POINT_WEIGHT
		if not R.FIXED.has(cats[i]):
			v += SAFETY * s / CAT_MAX[cats[i]]
		if v > best_value:
			best_value = v
			best_cell = i
	return {"cell": best_cell, "value": best_value}
