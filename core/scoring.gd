class_name Scoring
extends RefCounted
## Point values and multipliers. Tune here.

const PLACE_POINTS := 1
const BLAST_POINTS := 500
const STAR_POINTS := 300
const PERFECT_POINTS := 5000
const POWER_CLEAR_POINTS := 10
## The streak counts clearing turns. It survives non-clearing turns until
## this many happen in a row, so setting up a combo doesn't break it.
const STREAK_GRACE := 3
## Each clear in the streak adds this to the multiplier, up to the cap.
const STREAK_STEP := 0.25
const STREAK_CAP := 3.0
const FEVER_STREAK := 6
const FEVER_MULT := 2.0


static func pop_points(size: int) -> int:
	return 10 * size * (size - 2)


static func cascade_mult(depth: int) -> float:
	return 1.0 + 0.5 * depth


## Points for one resolution step, before the streak multiplier.
## Blasting several units at once is worth units^2 x BLAST_POINTS.
static func step_points(step: Dictionary) -> int:
	var pts := 0
	for p: Dictionary in step.pops:
		pts += pop_points(p.cells.size())
		if p.result == Rules.STAR:
			pts += STAR_POINTS
	var units: int = step.units.size()
	pts += BLAST_POINTS * units * units
	return roundi(pts * cascade_mult(step.depth))


static func is_fever(streak: int) -> bool:
	return streak >= FEVER_STREAK


## x1 for the first clear, then +0.25 per clear in the streak up to x3,
## doubled during Fever.
static func streak_mult(streak: int) -> float:
	var mult := minf(1.0 + STREAK_STEP * maxi(streak - 1, 0), STREAK_CAP)
	return mult * FEVER_MULT if is_fever(streak) else mult
