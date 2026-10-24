class_name DiscNode
extends Node3D
## One disc standing in the rack. The origin is its centre; the body inside
## turns round to show the other side, and a locked disc wears a gold ring.

var side := 0
var locked := false
var body := MeshInstance3D.new()
var _ring: MeshInstance3D


func _init(s: int = 0) -> void:
	body.mesh = FlipArt.disc_mesh()
	body.material_override = FlipArt.disc_material()
	add_child(body)
	show_side(s)


func show_side(s: int) -> void:
	side = s
	body.basis = FlipArt.face_basis(s)


## The gold ring and centre stud of a locked disc; they pop on when `animate`.
func set_locked(on: bool, animate: bool = false) -> void:
	locked = on
	if on and _ring == null:
		_ring = MeshInstance3D.new()
		_ring.mesh = FlipArt.ring_mesh()
		_ring.rotation.x = PI * 0.5
		_ring.position.z = 0.05
		_ring.material_override = BoardKit.candy(Palette.GOLD, 0.12)
		_ring.set_instance_shader_parameter("glow", 0.6)
		add_child(_ring)
		var stud := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.1
		sphere.height = 0.08
		stud.mesh = sphere
		# The ring is turned to face the player, so its +Y points out of the face.
		stud.position.y = FlipArt.HALF - 0.03
		stud.material_override = BoardKit.candy(Palette.GOLD, 0.08)
		_ring.add_child(stud)
	if _ring == null:
		return
	_ring.visible = on
	if on and animate:
		_ring.scale = Vector3.ONE * 1.8
		create_tween().tween_property(_ring, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_glow(v: float) -> void:
	body.set_instance_shader_parameter("glow", v)


func set_flash(v: float) -> void:
	body.set_instance_shader_parameter("flash", v)


func set_dimmed(v: float) -> void:
	body.set_instance_shader_parameter("dim", v)
	if _ring != null:
		_ring.set_instance_shader_parameter("dim", v)


func flash(time: float = 0.3) -> void:
	create_tween().tween_method(set_flash, 1.0, 0.0, time)
