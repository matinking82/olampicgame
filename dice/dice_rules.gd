class_name DiceRules
extends RefCounted
## Tic Tac Roll's rules, with no state of their own: the dice categories and
## what five dice score in each, the 4x4 board and its lines, and which cells
## a side may claim with the dice it rolled.
##
## Cells are indexed y * 4 + x, row 0 at the far side. A cell's owner is
## NONE, 0 (Sun, X) or 1 (Ice, O); an owned cell remembers the score that
## claimed it, and only a strictly higher score in its category can steal it.

const SIZE := 4
const CELLS := 16
## Owning this many cells in a row (across, down or diagonally) wins.
const LINE := 4
const DICE := 5
const ROLLS := 3
const NONE := -1

enum Cat { ONES, TWOS, THREES, FOURS, FIVES, SIXES, CHANCE, TWO_PAIRS, THREE_KIND, FOUR_KIND,
	FULL_HOUSE, SMALL_STRAIGHT, BIG_STRAIGHT, FIVE_KIND }

## The 16 categories every board is dealt from, shuffled each round.
const DECK := [Cat.ONES, Cat.TWOS, Cat.THREES, Cat.FOURS, Cat.FIVES, Cat.SIXES, Cat.CHANCE, Cat.CHANCE,
	Cat.TWO_PAIRS, Cat.THREE_KIND, Cat.THREE_KIND, Cat.FOUR_KIND, Cat.FULL_HOUSE, Cat.SMALL_STRAIGHT,
	Cat.BIG_STRAIGHT, Cat.FIVE_KIND]
## Category names for the HUD.
const NAMES := ["1s", "2s", "3s", "4s", "5s", "6s", "Chance", "Two Pairs", "3 of a Kind", "4 of a Kind",
	"Full House", "Small Straight", "Big Straight", "5 of a Kind"]
## Categories that always score the same; they can never be stolen.
const FIXED := {Cat.FULL_HOUSE: 25, Cat.SMALL_STRAIGHT: 30, Cat.BIG_STRAIGHT: 40, Cat.FIVE_KIND: 50}
## The face-count categories need at least this many of their face.
const UPPER_MIN := 2

static var _lines: Array[PackedInt32Array] = []


static func idx(x: int, y: int) -> int:
	return y * SIZE + x


static func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < SIZE and y >= 0 and y < SIZE


static func is_upper(cat: int) -> bool:
	return cat <= Cat.SIXES


## How many of each face (index 1-6) the dice show.
static func counts(dice: PackedInt32Array) -> PackedInt32Array:
	var c := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	for d in dice:
		c[d] += 1
	return c


## What the dice score in a category, or -1 when they don't fit it.
static func score(cat: int, dice: PackedInt32Array) -> int:
	var total := 0
	for d in dice:
		total += d
	return score_counts(cat, counts(dice), total)


## score() from precomputed face counts and dice total (the CPU calls this a lot).
static func score_counts(cat: int, c: PackedInt32Array, total: int) -> int:
	if cat <= Cat.SIXES:
		var face := cat + 1
		return face * c[face] if c[face] >= UPPER_MIN else -1
	var most := 0
	var pairs := 0
	var has_three := false
	var has_two := false
	for f in range(1, 7):
		most = maxi(most, c[f])
		if c[f] >= 2:
			pairs += 1
		if c[f] == 3:
			has_three = true
		elif c[f] == 2:
			has_two = true
	match cat:
		Cat.CHANCE:
			return total
		Cat.TWO_PAIRS:
			return total if pairs >= 2 else -1
		Cat.THREE_KIND:
			return total if most >= 3 else -1
		Cat.FOUR_KIND:
			return total if most >= 4 else -1
		Cat.FULL_HOUSE:
			# Five of a kind counts as a full house too.
			return 25 if (has_three and has_two) or most == 5 else -1
		Cat.SMALL_STRAIGHT:
			for start in range(1, 4):
				if c[start] > 0 and c[start + 1] > 0 and c[start + 2] > 0 and c[start + 3] > 0:
					return 30
			return -1
		Cat.BIG_STRAIGHT:
			if c[2] > 0 and c[3] > 0 and c[4] > 0 and c[5] > 0 and (c[1] > 0 or c[6] > 0):
				return 40
			return -1
		Cat.FIVE_KIND:
			return 50 if most == 5 else -1
	return -1


static func is_five_kind(dice: PackedInt32Array) -> bool:
	return dice.size() == DICE and score(Cat.FIVE_KIND, dice) > 0


## Whether `side` may claim cell i with these dice: they must fit its
## category, and an enemy cell needs a strictly higher score to be stolen.
static func can_claim(cats: PackedInt32Array, owners: PackedInt32Array, marks: PackedInt32Array,
		i: int, side: int, dice: PackedInt32Array) -> bool:
	if i < 0 or i >= CELLS or owners[i] == side:
		return false
	var s := score(cats[i], dice)
	return s >= 0 and (owners[i] == NONE or s > marks[i])


static func claimable(cats: PackedInt32Array, owners: PackedInt32Array, marks: PackedInt32Array,
		side: int, dice: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in CELLS:
		if can_claim(cats, owners, marks, i, side, dice):
			out.append(i)
	return out


## Every run of LINE cells in a row: across, down and both diagonals.
static func lines() -> Array[PackedInt32Array]:
	if _lines.is_empty():
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
			for y in SIZE:
				for x in SIZE:
					var end := Vector2i(x, y) + dir * (LINE - 1)
					if not in_bounds(end.x, end.y):
						continue
					var line := PackedInt32Array()
					for k in LINE:
						line.append(idx(x + dir.x * k, y + dir.y * k))
					_lines.append(line)
	return _lines


## The first line `side` owns completely, or an empty array.
static func winning_line(owners: PackedInt32Array, side: int) -> PackedInt32Array:
	for line in lines():
		var full := true
		for i in line:
			if owners[i] != side:
				full = false
				break
		if full:
			return line
	return PackedInt32Array()


static func count_owned(owners: PackedInt32Array, side: int) -> int:
	var n := 0
	for o in owners:
		if o == side:
			n += 1
	return n


static func is_full(owners: PackedInt32Array) -> bool:
	return not owners.has(NONE)
