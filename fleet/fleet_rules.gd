class_name FleetRules
extends RefCounted
## Mine Fleet's rules: Battleship crossed with Minesweeper. Each side hides
## a fleet of straight ships on an n x n sea (index y * n + x); ships never
## touch, not even corner to corner. Firing at a square either HITS a ship
## or misses, and a miss shows how many ship squares touch it (all 8
## around), like a Minesweeper number. A miss with no ships around opens
## the calm sea around it too. A ship whose every square is hit is SUNK,
## and the water round it opens up.
##
## A side's view of the enemy sea is an array of UNKNOWN, WATER (shown with
## its number), HIT or SUNK.

const UNKNOWN := 0
const WATER := 1
const HIT := 2
const SUNK := 3
## Ship ids are 0 and up; this marks open sea in a fleet.
const SEA := -1


static func neighbours(n: int, i: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var x := i % n
	var y := i / n
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and ny >= 0 and nx < n and ny < n:
				out.append(ny * n + nx)
	return out


static func orthogonal(n: int, i: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var x := i % n
	var y := i / n
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx := x + d.x
		var ny := y + d.y
		if nx >= 0 and ny >= 0 and nx < n and ny < n:
			out.append(ny * n + nx)
	return out


## Places the ships at random, none touching. Returns the fleet: a ship id
## per square, or SEA.
static func place_fleet(n: int, lengths: Array, rng: RandomNumberGenerator) -> PackedInt32Array:
	for attempt in 500:
		var fleet := PackedInt32Array()
		fleet.resize(n * n)
		fleet.fill(SEA)
		var ok := true
		for id in lengths.size():
			if not _place_ship(fleet, n, id, lengths[id], rng):
				ok = false
				break
		if ok:
			return fleet
	push_error("Could not place the fleet")
	return PackedInt32Array()


static func _place_ship(fleet: PackedInt32Array, n: int, id: int, length: int, rng: RandomNumberGenerator) -> bool:
	for attempt in 200:
		var across := rng.randf() < 0.5
		var x := rng.randi_range(0, n - (length if across else 1))
		var y := rng.randi_range(0, n - (1 if across else length))
		var cells := PackedInt32Array()
		for k in length:
			cells.append((y + (0 if across else k)) * n + x + (k if across else 0))
		if _fits(fleet, n, cells):
			for c in cells:
				fleet[c] = id
			return true
	return false


## Whether a ship can go on these squares: all open sea, nothing touching.
static func _fits(fleet: PackedInt32Array, n: int, cells: PackedInt32Array) -> bool:
	for c in cells:
		if fleet[c] != SEA:
			return false
		for m in neighbours(n, c):
			if fleet[m] != SEA:
				return false
	return true


## A fleet from text rows: a letter is a ship (the same letter is the same
## ship, "a" first), anything else open sea.
static func fleet_from_rows(rows: Array) -> PackedInt32Array:
	var n := rows.size()
	var fleet := PackedInt32Array()
	fleet.resize(n * n)
	fleet.fill(SEA)
	for y in n:
		var row: String = rows[y]
		for x in n:
			var ch := row.unicode_at(x)
			if ch >= 97 and ch <= 122:
				fleet[y * n + x] = ch - 97
	return fleet


static func ship_count(fleet: PackedInt32Array) -> int:
	var top := -1
	for v in fleet:
		top = maxi(top, v)
	return top + 1


static func ship_cells(fleet: PackedInt32Array, id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in fleet.size():
		if fleet[i] == id:
			out.append(i)
	return out


## How many ship squares touch a square (all 8 around).
static func number(fleet: PackedInt32Array, n: int, i: int) -> int:
	var c := 0
	for m in neighbours(n, i):
		if fleet[m] != SEA:
			c += 1
	return c


## Fires at square `i` of `fleet`, updating `seen` (the shooter's view).
## Returns {"hit": bool, "sunk": ship id or -1, "sunk_cells", "opened":
## the water squares it revealed, in order outward}.
static func fire(fleet: PackedInt32Array, seen: PackedInt32Array, n: int, i: int) -> Dictionary:
	var result := {"hit": false, "sunk": -1, "sunk_cells": PackedInt32Array(), "opened": PackedInt32Array()}
	if seen[i] != UNKNOWN:
		return result
	if fleet[i] == SEA:
		result.opened = open_water(fleet, seen, n, [i])
		return result
	result.hit = true
	seen[i] = HIT
	var id := fleet[i]
	var cells := ship_cells(fleet, id)
	for c in cells:
		if seen[c] != HIT:
			return result
	result.sunk = id
	result.sunk_cells = cells
	var ring := []
	for c in cells:
		seen[c] = SUNK
		for m in neighbours(n, c):
			if seen[m] == UNKNOWN and fleet[m] == SEA and not ring.has(m):
				ring.append(m)
	result.opened = open_water(fleet, seen, n, ring)
	return result


## Reveals sea squares, spreading on through any with no ships around.
static func open_water(fleet: PackedInt32Array, seen: PackedInt32Array, n: int, start: Array) -> PackedInt32Array:
	var opened := PackedInt32Array()
	var queue := start.duplicate()
	while not queue.is_empty():
		var c: int = queue.pop_front()
		if seen[c] != UNKNOWN or fleet[c] != SEA:
			continue
		seen[c] = WATER
		opened.append(c)
		if number(fleet, n, c) == 0:
			for m in neighbours(n, c):
				if seen[m] == UNKNOWN:
					queue.append(m)
	return opened


## Every ship square has been hit.
static func all_sunk(fleet: PackedInt32Array, seen: PackedInt32Array) -> bool:
	for i in fleet.size():
		if fleet[i] != SEA and seen[i] != SUNK:
			return false
	return true


## The lengths of the ships not yet sunk.
static func afloat(fleet: PackedInt32Array, seen: PackedInt32Array) -> Array:
	var out := []
	for id in ship_count(fleet):
		var cells := ship_cells(fleet, id)
		if seen[cells[0]] != SUNK:
			out.append(cells.size())
	return out


## The numbers a side can see: each revealed water square's, else -1.
static func visible_numbers(fleet: PackedInt32Array, seen: PackedInt32Array, n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(seen.size())
	for i in seen.size():
		out[i] = number(fleet, n, i) if seen[i] == WATER else -1
	return out


## Ship squares in a row and a column (the SONAR power).
static func line_counts(fleet: PackedInt32Array, n: int, i: int) -> Vector2i:
	var row := 0
	var col := 0
	for k in n:
		if fleet[(i / n) * n + k] != SEA:
			row += 1
		if fleet[k * n + i % n] != SEA:
			col += 1
	return Vector2i(row, col)
