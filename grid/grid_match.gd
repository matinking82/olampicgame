class_name GridMatch
extends RefCounted
## A Code Grid run: a ladder of levels, each a secret Latin-square code to
## crack within a number of CHECKS. Some squares start revealed (givens).
## Fill the grid so every row and column uses each digit once, CHECK it,
## and every row and column tells you how many of its squares are right.
## Crack the code to climb a level (bigger grids, fewer givens); run out
## of checks and it costs a heart, and you try a fresh code at the same
## level. The run ends when the hearts run out.
##
## Points: every check scores for the squares it has right; cracking a code
## scores for its size, every check left over, and doing it in PAR checks
## or fewer. Cracked codes in a row build a streak that multiplies the
## cracking points, and four in a row is Fever. Points fill a power meter
## that earns charges for REVEAL (uncover one square) and TEST (ask whether
## one square is right).

const R := preload("res://grid/grid_rules.gd")

const HIT_POINTS := 15
## Cracking a code, per square of the grid.
const CRACK_POINTS := 60
const SPARE_POINTS := 300
const PAR_POINTS := 500
const STREAK_STEP := 0.25
const STREAK_CAP := 3.0
const FEVER_STREAK := 4
const FEVER_MULT := 2.0
const METER_GOAL := 1500
const MAX_CHARGES := 3
const HEARTS := 3
## Levels: grid size, givens, checks allowed and par.
const LEVELS := [
	{"n": 4, "givens": 3, "checks": 6, "par": 3},
	{"n": 4, "givens": 2, "checks": 6, "par": 3},
	{"n": 4, "givens": 0, "checks": 6, "par": 3},
	{"n": 5, "givens": 6, "checks": 7, "par": 4},
	{"n": 5, "givens": 3, "checks": 7, "par": 4},
	{"n": 5, "givens": 0, "checks": 7, "par": 4},
	{"n": 6, "givens": 10, "checks": 8, "par": 5},
	{"n": 6, "givens": 7, "checks": 8, "par": 5},
	{"n": 6, "givens": 5, "checks": 8, "par": 5},
]
## The "codes left" counter stops counting here, and gives up after this
## many search steps (then it shows the count as "at least").
const COUNT_CAP := 999
const COUNT_BUDGET := 250000

var level := 1
var n := 4
var code := PackedInt32Array()
## Square -> digit, for the squares shown from the start (and revealed).
var givens := {}
## The player's grid (0 is empty).
var grid := PackedInt32Array()
## Every check so far: {"guess", "rows", "cols", "hits"}.
var checks: Array[Dictionary] = []
var max_checks := 6
var par := 3
## Square -> digits a TEST proved wrong there.
var ruled_out := {}
var hearts := HEARTS
var score := 0
var streak := 0
var charges := 0
var meter := 0
var solved := false
var failed := false
var game_over := false
var rng := RandomNumberGenerator.new()

var levels_cracked := 0
var best_streak := 0
var perfect := 0
var total_checks := 0


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func start() -> void:
	level = 1
	hearts = HEARTS
	score = 0
	streak = 0
	charges = 0
	meter = 0
	levels_cracked = 0
	game_over = false
	start_level()


static func setup(lv: int) -> Dictionary:
	return LEVELS[mini(lv, LEVELS.size()) - 1]


## A fresh code for the level.
func start_level() -> void:
	var s := setup(level)
	n = s.n
	max_checks = s.checks
	par = s.par
	var c := R.random_square(n, rng)
	set_code(c, R.make_givens(c, n, s.givens, rng))


## Sets the code and givens (a new level, the tutorial, tests).
func set_code(c: PackedInt32Array, shown: Dictionary) -> void:
	code = c
	n = roundi(sqrt(c.size()))
	givens = shown.duplicate()
	grid = PackedInt32Array()
	grid.resize(n * n)
	for i: int in givens:
		grid[i] = givens[i]
	checks.clear()
	ruled_out.clear()
	solved = false
	failed = false


func checks_left() -> int:
	return max_checks - checks.size()


func is_running() -> bool:
	return not solved and not failed


func is_given(i: int) -> bool:
	return givens.has(i)


## Puts a digit in a square (0 clears it). Givens can't change.
func place(i: int, v: int) -> bool:
	if not is_running() or i < 0 or i >= grid.size() or is_given(i) or v < 0 or v > n:
		return false
	grid[i] = v
	return true


func conflicts() -> PackedInt32Array:
	return R.conflicts(grid, n)


## Why the grid can't be checked yet, or "" when it can.
func check_blocker() -> String:
	if not is_running():
		return "done"
	if checks_left() <= 0:
		return "No checks left"
	if not R.is_full(grid):
		return "Fill every square first"
	if not conflicts().is_empty():
		return "A row or column repeats a digit"
	return ""


## Checks the grid against the code and returns the counts and what
## happened: a crack (with its points) or the last check used up.
func check() -> Dictionary:
	if check_blocker() != "":
		return {}
	var fb := R.feedback(code, grid, n)
	var hits := 0
	for v in fb.rows:
		hits += v
	var entry := {"guess": grid.duplicate(), "rows": fb.rows, "cols": fb.cols, "hits": hits}
	checks.append(entry)
	total_checks += 1
	var result := entry.duplicate()
	result.solved = hits == n * n
	result.failed = false
	result.check_points = HIT_POINTS * hits
	result.crack_points = 0
	result.perfect = false
	result.charges_earned = 0
	var points: int = result.check_points
	if result.solved:
		solved = true
		levels_cracked += 1
		streak += 1
		best_streak = maxi(best_streak, streak)
		result.perfect = checks.size() <= par
		if result.perfect:
			perfect += 1
		var base := CRACK_POINTS * n * n + SPARE_POINTS * checks_left() + (PAR_POINTS if result.perfect else 0)
		result.crack_points = roundi(base * streak_mult())
		points += result.crack_points
	elif checks_left() <= 0:
		failed = true
		result.failed = true
		streak = 0
		hearts -= 1
		game_over = hearts <= 0
	result.points = points
	result.streak = streak
	result.fever = is_fever()
	result.mult = streak_mult()
	score += points
	meter += points
	while meter >= METER_GOAL:
		meter -= METER_GOAL
		if charges < MAX_CHARGES:
			charges += 1
			result.charges_earned += 1
	return result


## After a level: a crack climbs, a failure tries a fresh code at the same level.
func next_level() -> void:
	if solved:
		level += 1
	start_level()


## Stars for a cracked code: 3 at par or better, 2 one over, else 1.
func stars() -> int:
	if not solved:
		return 0
	return 3 if checks.size() <= par else (2 if checks.size() == par + 1 else 1)


# --- Powers ------------------------------------------------------------------------

func can_use_power() -> bool:
	return is_running() and charges > 0


## REVEAL: a square that isn't right yet becomes a given. Returns it, or -1.
func reveal() -> int:
	if not can_use_power():
		return -1
	var wrong: Array[int] = []
	var open: Array[int] = []
	for i in grid.size():
		if is_given(i):
			continue
		open.append(i)
		if grid[i] != code[i]:
			wrong.append(i)
	var pool := wrong if not wrong.is_empty() else open
	if pool.is_empty():
		return -1
	charges -= 1
	var i := pool[rng.randi_range(0, pool.size() - 1)]
	givens[i] = code[i]
	grid[i] = code[i]
	return i


## TEST: whether a filled square is right. A wrong digit is remembered as
## ruled out there.
func test(i: int) -> int:
	if not can_use_power() or grid[i] == R.EMPTY or is_given(i):
		return -1
	charges -= 1
	if grid[i] == code[i]:
		givens[i] = code[i]
		return 1
	var out: Array = ruled_out.get(i, [])
	if not out.has(grid[i]):
		out.append(grid[i])
	ruled_out[i] = out
	return 0


# --- Points --------------------------------------------------------------------------

func streak_mult() -> float:
	var m := minf(1.0 + STREAK_STEP * (streak - 1), STREAK_CAP) if streak > 0 else 1.0
	return m * (FEVER_MULT if is_fever() else 1.0)


func is_fever() -> bool:
	return streak >= FEVER_STREAK


func meter_fill() -> float:
	return float(meter) / METER_GOAL


## How many codes still fit the clues: {"count", "complete"}. Slow on
## big grids; the game runs it on a thread.
static func count_codes(size: int, shown: Dictionary, clue_list: Array) -> Dictionary:
	var found := R.solve(size, shown, clue_list, COUNT_CAP, null, COUNT_BUDGET)
	return {"count": found.count, "complete": found.complete}


## The clues so far, for the solver.
func clues() -> Array:
	var out := []
	for c in checks:
		out.append({"guess": c.guess, "rows": c.rows, "cols": c.cols})
	return out
