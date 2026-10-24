class_name DieNode
extends Node3D
## One die. The origin is the centre of its bottom face, so squash and
## stretch scale from the floor; the body inside turns to show a value.

var value := 1
var side := 0
var body := MeshInstance3D.new()


func _init(owner_side: int = 0, v: int = 1) -> void:
	body.mesh = DiceArt.die_mesh()
	body.position.y = DiceArt.DIE_SIZE * 0.5
	add_child(body)
	set_side(owner_side)
	show_value(v)


func set_side(s: int, fever: bool = false) -> void:
	side = s
	body.material_override = DiceArt.fever_die_material(s) if fever and s >= 0 else DiceArt.die_material(s)


## Shows face `v` on top, turned `yaw` radians.
func show_value(v: int, yaw: float = 0.0) -> void:
	value = v
	body.basis = DiceArt.face_basis(v, yaw)


func set_glow(v: float) -> void:
	body.set_instance_shader_parameter("glow", v)


func set_flash(v: float) -> void:
	body.set_instance_shader_parameter("flash", v)


func set_dimmed(v: float) -> void:
	body.set_instance_shader_parameter("dim", v)


func flash(time: float = 0.3) -> void:
	create_tween().tween_method(set_flash, 1.0, 0.0, time)
