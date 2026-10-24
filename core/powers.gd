class_name Powers
extends RefCounted
## The player's power slots, the power meter and pending wild tiles.

enum Kind { LASER, BOMB, NUKE, HAMMER, REROLL }

const MAX_SLOTS := 3
## Points paid instead when a power is earned with every slot full.
const OVERFLOW_POINTS := 250
## Points needed to fill the meter, which pays out a Hammer.
const METER_GOAL := 2500
## A Reroll is earned every time the score passes a multiple of this.
const REROLL_EVERY := 10000

var slots: Array[int] = []
var meter := 0
## Wild cells still owed to the tray, one per Sudoku Blast.
var pending_wilds := 0


## The power a pop of this size drops, or -1 for none.
static func for_pop(size: int) -> int:
	if size >= 6:
		return Kind.NUKE
	if size == 5:
		return Kind.BOMB
	if size == 4:
		return Kind.LASER
	return -1


static func needs_target(kind: int) -> bool:
	return kind != Kind.REROLL


static func kind_name(kind: int) -> String:
	match kind:
		Kind.LASER:
			return "Line Laser"
		Kind.BOMB:
			return "Bomb"
		Kind.NUKE:
			return "Number Nuke"
		Kind.HAMMER:
			return "Hammer"
		Kind.REROLL:
			return "Reroll"
	return "?"


## Returns false when every slot is full.
func add(kind: int) -> bool:
	if slots.size() >= MAX_SLOTS:
		return false
	slots.append(kind)
	return true


func take(slot: int) -> int:
	var kind := slots[slot]
	slots.remove_at(slot)
	return kind


## Adds points to the meter and returns how many times it filled.
func charge(points: int) -> int:
	meter += points
	var filled := meter / METER_GOAL
	meter %= METER_GOAL
	return filled


func meter_ratio() -> float:
	return float(meter) / METER_GOAL
