class_name Palette
extends RefCounted
## Every colour in the game. Digits run around the rainbow, 1 red to 9 pink.

const DIGITS := [
	Color("ff3b5c"), Color("ff8a1f"), Color("ffc61a"),
	Color("8fdd2a"), Color("22cf78"), Color("1fc8e0"),
	Color("3d82ff"), Color("8f5bff"), Color("ff4fcf"),
]
const WILD := Color("fff1c9")
const STONE := Color("9a9fb8")
const STONE_CRACKED := Color("62677f")
const INVALID := Color("ff2240")
const DIM := Color("4d4f6e")

const BOARD := Color("1b1440")
const CELL_A := Color("2a2160")
const CELL_B := Color("3a2d80")
const LINE := Color("ffc8f0")
const PAD := Color(0.13, 0.06, 0.32, 0.78)

const TEXT := Color("fffaff")
const INK := Color("1a0f3d")
const GOLD := Color("ffd21f")
const HOT := Color("ff4f8b")


static func tile(v: int) -> Color:
	if Board.is_digit(v):
		return DIGITS[v - 1]
	match v:
		Board.WILD:
			return WILD
		Board.STONE:
			return STONE
		Board.STONE_CRACKED:
			return STONE_CRACKED
	return INVALID


static func power(kind: int) -> Color:
	match kind:
		Powers.Kind.LASER:
			return Color("19b8d6")
		Powers.Kind.BOMB:
			return Color("ff6a2b")
		Powers.Kind.NUKE:
			return Color("3fc95a")
		Powers.Kind.HAMMER:
			return Color("8f5bff")
		Powers.Kind.REROLL:
			return Color("ff4fcf")
	return DIM
