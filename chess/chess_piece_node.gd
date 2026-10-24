class_name ChessPieceNode
extends Node3D
## One chess piece on the board. The origin is the centre of its foot, so
## squash-and-stretch scales from the floor.

const R := preload("res://chess/chess_rules.gd")
## Knights turn this far from straight ahead so their profile shows.
const KNIGHT_TURN := 55.0
## Pieces are modelled a bit small for a 1-unit square; this sizes them up.
const SIZE := 1.2

var piece := 0
var body := MeshInstance3D.new()


func _init(p: int = 0) -> void:
	body.scale = Vector3.ONE * SIZE
	add_child(body)
	if p != 0:
		set_piece(p)


func set_piece(p: int) -> void:
	piece = p
	var type := R.type_of(p)
	body.mesh = ChessArt.mesh(type)
	body.material_override = ChessArt.material(p)
	# Face the enemy: side 0 looks up the board (-Z), side 1 down it.
	var facing := 180.0 if R.side_of(p) == 0 else 0.0
	if type == R.KNIGHT:
		facing += -KNIGHT_TURN if R.side_of(p) == 0 else KNIGHT_TURN
	body.rotation_degrees.y = facing


func set_glow(v: float) -> void:
	body.set_instance_shader_parameter("glow", v)


func set_flash(v: float) -> void:
	body.set_instance_shader_parameter("flash", v)


func set_dimmed(v: float) -> void:
	body.set_instance_shader_parameter("dim", v)


## A white flash that fades out.
func flash(time: float = 0.3) -> void:
	create_tween().tween_method(set_flash, 1.0, 0.0, time)
