class_name PieceGenerator
extends RefCounted
## Deals tray pieces. Seeded, so a seed always replays the same run.

const TRAY_SIZE := 3
const DEAL_ATTEMPTS := 24
## Caps how strongly a useful digit is favoured, so deals stay varied.
const MAX_BONUS := 6.0

const SHAPES := {
	"mono": [Vector2i(0, 0)],
	"duo": [Vector2i(0, 0), Vector2i(1, 0)],
	"trio": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
	"corner": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
	"quad": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
	"square": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"ell": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)],
	"tee": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
	"zig": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
}

var rng := RandomNumberGenerator.new()


func _init(seed_value: int) -> void:
	rng.seed = seed_value


func deal(board: Board, level: int) -> Array[Piece]:
	var tray: Array[Piece] = []
	for attempt in DEAL_ATTEMPTS:
		tray.clear()
		for i in TRAY_SIZE:
			tray.append(make_piece(board, level))
		if not Difficulty.guarantee_fit(level):
			break
		if tray.any(func(p: Piece) -> bool: return Rules.fits_any_rotation(board, p)):
			break
	return tray


func make_piece(board: Board, level: int) -> Piece:
	var shape: Array = SHAPES[_pick_shape(Difficulty.shape_weights(level))]
	var weights := digit_weights(board, Difficulty.digit_mode(level))
	var vals: Array[int] = []
	for i in shape.size():
		vals.append(_pick_digit(weights))
	var piece := Piece.make(shape, vals)
	for r in rng.randi_range(0, 3):
		piece = piece.rotated()
	return piece


## Odds for digits 1-9 (index 0 unused). HELPFUL favours digits that would
## pop a group or finish a nearly complete unit; TOUGH avoids them.
func digit_weights(board: Board, mode: Difficulty.DigitMode) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(10)
	w.fill(1.0)
	w[0] = 0.0
	if mode == Difficulty.DigitMode.NEUTRAL:
		return w
	var opps := Rules.pop_opportunities(board)
	var needs := Rules.sudoku_needs(board)
	for d in range(1, 10):
		var bonus := minf(1.5 * opps[d] + 2.0 * needs[d], MAX_BONUS)
		if mode == Difficulty.DigitMode.HELPFUL:
			w[d] += bonus
		else:
			w[d] = 1.0 / (1.0 + 0.5 * bonus)
	return w


func _pick_shape(weights: Dictionary) -> String:
	var total := 0.0
	for k: String in weights:
		total += weights[k]
	var roll := rng.randf() * total
	for k: String in weights:
		roll -= weights[k]
		if roll <= 0.0:
			return k
	return weights.keys().back()


func _pick_digit(weights: PackedFloat32Array) -> int:
	var total := 0.0
	for d in range(1, 10):
		total += weights[d]
	var roll := rng.randf() * total
	for d in range(1, 10):
		roll -= weights[d]
		if roll <= 0.0:
			return d
	return 9
