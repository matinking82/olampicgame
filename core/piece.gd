class_name Piece
extends RefCounted
## A tray piece: a small shape where every cell carries its own value
## (a digit 1-9 or Board.WILD). Offsets are kept normalised to start at (0, 0).

var offsets: Array[Vector2i] = []
var values := PackedInt32Array()


static func make(shape: Array, vals: Array) -> Piece:
	var p := Piece.new()
	for o: Vector2i in shape:
		p.offsets.append(o)
	p.values = PackedInt32Array(vals)
	p._normalize()
	return p


func size() -> int:
	return offsets.size()


func cells_at(origin: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for o in offsets:
		out.append(origin + o)
	return out


func value_at(offset: Vector2i) -> int:
	var i := offsets.find(offset)
	return values[i] if i >= 0 else Board.EMPTY


## Width and height in cells.
func extent() -> Vector2i:
	var e := Vector2i.ZERO
	for o in offsets:
		e.x = maxi(e.x, o.x + 1)
		e.y = maxi(e.y, o.y + 1)
	return e


## 90 degrees clockwise on a y-down grid.
func rotated() -> Piece:
	var p := Piece.new()
	for o in offsets:
		p.offsets.append(Vector2i(-o.y, o.x))
	p.values = values.duplicate()
	p._normalize()
	return p


func copy() -> Piece:
	var p := Piece.new()
	p.offsets = offsets.duplicate()
	p.values = values.duplicate()
	return p


func has_wild() -> bool:
	return values.has(Board.WILD)


func _normalize() -> void:
	if offsets.is_empty():
		return
	var lo := offsets[0]
	for o in offsets:
		lo.x = mini(lo.x, o.x)
		lo.y = mini(lo.y, o.y)
	for i in offsets.size():
		offsets[i] -= lo
