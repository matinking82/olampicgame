class_name PieceNode
extends Node3D
## A tray piece drawn as tiles, centred on its own origin.

var piece: Piece
var tiles: Array[TileNode] = []


func _init(p: Piece) -> void:
	piece = p
	var ext := p.extent()
	for i in p.size():
		var o := p.offsets[i]
		var t := TileNode.new(p.values[i])
		t.position = Vector3(o.x - (ext.x - 1) * 0.5, 0.0, o.y - (ext.y - 1) * 0.5)
		add_child(t)
		tiles.append(t)


## Offset from this node's origin to the centre of the piece's (0, 0) cell,
## at full scale.
func first_cell_offset() -> Vector3:
	var ext := piece.extent()
	return Vector3(-(ext.x - 1) * 0.5, 0.0, -(ext.y - 1) * 0.5)


func set_dimmed(on: bool) -> void:
	for t in tiles:
		t.set_dimmed(on)
