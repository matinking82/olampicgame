class_name Difficulty
extends RefCounted
## How the run gets harder. Levels come from turns played, not score, so
## the pacing is the same for everyone and score stays a pure reward.
## Tuned with tools/simulate.gd: a good run lasts about 10-20 minutes.

enum DigitMode { HELPFUL, NEUTRAL, TOUGH }

const TURNS_PER_LEVEL := 24


static func level_for(turns: int) -> int:
	return 1 + turns / TURNS_PER_LEVEL


## Turns needed to reach a level.
static func threshold(level: int) -> int:
	return (level - 1) * TURNS_PER_LEVEL


## Relative odds of each piece shape (names from PieceGenerator.SHAPES).
static func shape_weights(level: int) -> Dictionary:
	if level <= 5:
		return {"mono": 3, "duo": 4, "trio": 2, "corner": 2}
	if level <= 9:
		return {"mono": 2, "duo": 4, "trio": 3, "corner": 3, "square": 1, "ell": 1}
	if level <= 12:
		return {"mono": 2, "duo": 3, "trio": 3, "corner": 3, "square": 1, "quad": 1, "ell": 1, "tee": 1}
	return {"mono": 1, "duo": 2, "trio": 3, "corner": 3, "square": 2, "quad": 2, "ell": 2, "tee": 2, "zig": 1}


static func digit_mode(level: int) -> DigitMode:
	if level <= 7:
		return DigitMode.HELPFUL
	if level <= 12:
		return DigitMode.NEUTRAL
	return DigitMode.TOUGH


## Early on, every deal contains at least one piece that fits.
static func guarantee_fit(level: int) -> bool:
	return level <= 8


## A stone drops every this many turns; 0 means never.
static func stone_every(level: int) -> int:
	if level < 9:
		return 0
	if level < 12:
		return 5
	if level < 15:
		return 3
	return 2
