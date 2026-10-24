class_name MarkNode
extends Node3D
## A claimed cell's mark: a candy X for Sun or an O for Ice. The origin is
## the centre of its foot, so squash and stretch scale from the floor.

var side := 0
var _parts: Array[MeshInstance3D] = []


func _init(s: int = 0) -> void:
	side = s
	if s == 0:
		for angle: float in [45.0, -45.0]:
			var bar := MeshInstance3D.new()
			bar.mesh = DiceArt.bar_mesh()
			bar.rotation_degrees.y = angle
			# The second bar sits a hair higher so the two don't flicker where they cross.
			bar.position.y = DiceArt.MARK_HEIGHT * 0.5 + (0.004 if angle < 0 else 0.0)
			_parts.append(bar)
	else:
		var ring := MeshInstance3D.new()
		ring.mesh = DiceArt.ring_mesh()
		ring.position.y = DiceArt.MARK_HEIGHT * 0.5 + 0.01
		_parts.append(ring)
	for p in _parts:
		p.material_override = DiceArt.mark_material(s)
		add_child(p)


func set_glow(v: float) -> void:
	for p in _parts:
		p.set_instance_shader_parameter("glow", v)


func set_flash(v: float) -> void:
	for p in _parts:
		p.set_instance_shader_parameter("flash", v)


func set_dimmed(v: float) -> void:
	for p in _parts:
		p.set_instance_shader_parameter("dim", v)


func flash(time: float = 0.3) -> void:
	create_tween().tween_method(set_flash, 1.0, 0.0, time)
