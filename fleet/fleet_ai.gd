class_name FleetAI
extends RefCounted
## Mine Fleet's CPU gunner. It only uses what it can see: its view of your
## sea, the numbers on the water it opened, and which ship lengths are
## still afloat. In order it:
##   1. rules squares out: corners of a hit (ships are straight and never
##      touch), and, when it reads numbers, every hidden square round a
##      number whose ships are all found;
##   2. fires at squares a number proves must be ships;
##   3. finishes a wounded ship along its line;
##   4. otherwise hunts where the most ways to fit the remaining ships
##      cross, leaning toward squares the numbers make likely.
## Easier rounds read fewer of the numbers and sometimes fire at random.

const R := preload("res://fleet/fleet_rules.gd")


## The square to fire at. `cfg` has "read" (the chance it takes in each
## number, 0-1) and "blunder" (the chance of a random shot).
static func choose(seen: PackedInt32Array, nums: PackedInt32Array, n: int, afloat: Array, cfg: Dictionary,
		rng: RandomNumberGenerator) -> int:
	var safe := {}
	var sure := {}
	var weight := {}
	var noticed := nums.duplicate()
	for i in noticed.size():
		if noticed[i] >= 0 and rng.randf() >= cfg.read:
			noticed[i] = -1
	_deduce(seen, noticed, n, safe, sure, weight)
	var open: Array[int] = []
	for i in seen.size():
		if seen[i] == R.UNKNOWN and not safe.has(i):
			open.append(i)
	if open.is_empty():
		for i in seen.size():
			if seen[i] == R.UNKNOWN:
				open.append(i)
	if open.is_empty():
		return -1
	if rng.randf() < cfg.blunder:
		return open[rng.randi_range(0, open.size() - 1)]
	if not sure.is_empty():
		var keys := sure.keys()
		return keys[rng.randi_range(0, keys.size() - 1)]
	var density := _density(seen, n, afloat, safe)
	var targets := _targets(seen, n, safe)
	var pool: Array[int] = targets if not targets.is_empty() else open
	var best := -1
	var best_v := -1.0
	for i in pool:
		var v := float(density.get(i, 0)) * (1.0 + 3.0 * float(weight.get(i, 0.0))) + rng.randf() * 0.01
		if v > best_v:
			best_v = v
			best = i
	return best


## Works out squares that can't be ships (`safe`), squares that must be
## (`sure`), and for the rest the best ship chance a number gives (`weight`).
static func _deduce(seen: PackedInt32Array, nums: PackedInt32Array, n: int,
		safe: Dictionary, sure: Dictionary, weight: Dictionary) -> void:
	for i in seen.size():
		if seen[i] == R.HIT or seen[i] == R.SUNK:
			var x := i % n
			var y := i / n
			for d: Vector2i in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx >= 0 and ny >= 0 and nx < n and ny < n and seen[ny * n + nx] == R.UNKNOWN:
					safe[ny * n + nx] = true
	# Three times round, so what one number settles can help the next.
	for pass_index in 3:
		for i in seen.size():
			if nums[i] < 0:
				continue
			var found := 0
			var hidden: Array[int] = []
			for m in R.neighbours(n, i):
				if seen[m] == R.HIT or seen[m] == R.SUNK or sure.has(m):
					found += 1
				elif seen[m] == R.UNKNOWN and not safe.has(m):
					hidden.append(m)
			var left := nums[i] - found
			if hidden.is_empty():
				continue
			if left <= 0:
				for m in hidden:
					safe[m] = true
			elif left >= hidden.size():
				for m in hidden:
					sure[m] = true
			else:
				var p := float(left) / hidden.size()
				for m in hidden:
					weight[m] = maxf(float(weight.get(m, 0.0)), p)


## Squares next to a wounded ship that could carry on its line.
static func _targets(seen: PackedInt32Array, n: int, safe: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for i in seen.size():
		if seen[i] != R.HIT:
			continue
		var x := i % n
		var y := i / n
		# If a neighbouring hit shows the ship's direction, only follow it.
		var across := (x > 0 and seen[i - 1] == R.HIT) or (x < n - 1 and seen[i + 1] == R.HIT)
		var down := (y > 0 and seen[i - n] == R.HIT) or (y < n - 1 and seen[i + n] == R.HIT)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if (across and d.y != 0) or (down and d.x != 0):
				continue
			var nx := x + d.x
			var ny := y + d.y
			while nx >= 0 and ny >= 0 and nx < n and ny < n and seen[ny * n + nx] == R.HIT:
				nx += d.x
				ny += d.y
			if nx >= 0 and ny >= 0 and nx < n and ny < n:
				var c := ny * n + nx
				if seen[c] == R.UNKNOWN and not safe.has(c) and not out.has(c):
					out.append(c)
	return out


## For each square, how many ways the ships still afloat could lie across
## it (through unknown or hit squares only).
static func _density(seen: PackedInt32Array, n: int, afloat: Array, safe: Dictionary) -> Dictionary:
	var out := {}
	for length: int in afloat:
		for y in n:
			for x in n:
				for across in [true, false]:
					if (across and x + length > n) or (not across and y + length > n):
						continue
					var cells: Array[int] = []
					var ok := true
					for k in length:
						var c := (y + (0 if across else k)) * n + x + (k if across else 0)
						var s := seen[c]
						if s == R.WATER or s == R.SUNK or safe.has(c):
							ok = false
							break
						cells.append(c)
					if ok:
						for c in cells:
							if seen[c] == R.UNKNOWN:
								out[c] = int(out.get(c, 0)) + 1
	return out
