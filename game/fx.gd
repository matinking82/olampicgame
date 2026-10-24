class_name Fx
extends Node3D
## One-shot effects: spark bursts, confetti, stone debris, shockwave rings,
## light beams and confetti rain. Positions are in this node's local space.
## Every effect frees itself when it's done.

static var _spark_mesh: SphereMesh
static var _debris_mesh: BoxMesh
static var _confetti_mesh: QuadMesh
static var _glow_mat: StandardMaterial3D
static var _confetti_mat: StandardMaterial3D
static var _shrink: Curve
static var _rainbow: Gradient


## A burst of glowing beads, e.g. when tiles pop.
func sparks(at: Vector3, color: Color, amount: int = 20, speed: float = 4.0, size: float = 1.0) -> void:
	var p := _emitter(amount, 0.6)
	p.mesh = _spark()
	p.material_override = _glow()
	p.position = at
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -10, 0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.6 * size
	p.scale_amount_max = 1.3 * size
	p.scale_amount_curve = _shrink_curve()
	p.color = Color(color.r * 2.2, color.g * 2.2, color.b * 2.2)
	_fire(p)


## Spinning paper confetti thrown upwards from a box-shaped area.
func confetti(at: Vector3, extents: Vector3 = Vector3(0.5, 0, 0.5), amount: int = 50, speed: float = 7.0) -> void:
	var p := _emitter(amount, 1.6)
	_paper(p)
	p.position = at
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -11, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	_fire(p)


## Confetti falling from above over an area, for level-ups and big moments.
func rain(at: Vector3, extents: Vector3, amount: int = 120) -> void:
	var p := _emitter(amount, 2.4)
	_paper(p)
	p.explosiveness = 0.6
	p.position = at + Vector3(0, 6, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3.DOWN
	p.spread = 20.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -4, 0)
	_fire(p)


## Chunky grey bits for cracking stones.
func debris(at: Vector3, color: Color, amount: int = 14) -> void:
	var p := _emitter(amount, 0.8)
	p.mesh = _debris()
	p.position = at + Vector3(0, 0.3, 0)
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -16, 0)
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.scale_amount_curve = _shrink_curve()
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	p.material_override = m
	_fire(p)


## A flat glowing ring that expands and fades: the shockwave of a hit.
func ring(at: Vector3, color: Color, radius: float = 1.6, time: float = 0.45) -> void:
	var r := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.82
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 6
	r.mesh = torus
	var m := _additive(color)
	r.material_override = m
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.position = at + Vector3(0, 0.15, 0)
	r.scale = Vector3(0.2, 0.05, 0.2)
	add_child(r)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(r, "scale", Vector3(radius, 0.05, radius), time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(r.queue_free)


## A bar of light across a row, column or box that flashes and fades.
func beam(center: Vector3, size: Vector3, color: Color, time: float = 0.5) -> void:
	var b := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	b.mesh = box
	var m := _additive(color)
	b.material_override = m
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.position = center + Vector3(0, size.y * 0.5, 0)
	b.scale = Vector3(1, 0.2, 1)
	add_child(b)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(b, "scale", Vector3(1.04, 1.0, 1.04), time * 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(b.queue_free)


func _emitter(amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _fire(p: CPUParticles3D) -> void:
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.2).timeout.connect(p.queue_free)


func _paper(p: CPUParticles3D) -> void:
	p.mesh = _confetti()
	p.material_override = _paper_material()
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	p.color_initial_ramp = _rainbow_ramp()


func _additive(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(color.r * 1.6, color.g * 1.6, color.b * 1.6, 0.9)
	m.no_depth_test = false
	return m


static func _spark() -> SphereMesh:
	if _spark_mesh == null:
		_spark_mesh = SphereMesh.new()
		_spark_mesh.radius = 0.09
		_spark_mesh.height = 0.18
		_spark_mesh.radial_segments = 8
		_spark_mesh.rings = 4
	return _spark_mesh


static func _debris() -> BoxMesh:
	if _debris_mesh == null:
		_debris_mesh = BoxMesh.new()
		_debris_mesh.size = Vector3(0.12, 0.1, 0.12)
	return _debris_mesh


static func _confetti() -> QuadMesh:
	if _confetti_mesh == null:
		_confetti_mesh = QuadMesh.new()
		_confetti_mesh.size = Vector2(0.26, 0.15)
	return _confetti_mesh


static func _glow() -> StandardMaterial3D:
	if _glow_mat == null:
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_mat.vertex_color_use_as_albedo = true
	return _glow_mat


static func _paper_material() -> StandardMaterial3D:
	if _confetti_mat == null:
		_confetti_mat = StandardMaterial3D.new()
		_confetti_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_confetti_mat.vertex_color_use_as_albedo = true
		_confetti_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_confetti_mat.billboard_keep_scale = true
		_confetti_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _confetti_mat


static func _shrink_curve() -> Curve:
	if _shrink == null:
		_shrink = Curve.new()
		_shrink.add_point(Vector2(0, 1))
		_shrink.add_point(Vector2(0.7, 0.8))
		_shrink.add_point(Vector2(1, 0))
	return _shrink


static func _rainbow_ramp() -> Gradient:
	if _rainbow == null:
		_rainbow = Gradient.new()
		_rainbow.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		var colors := PackedColorArray()
		var offsets := PackedFloat32Array()
		for i in Palette.DIGITS.size():
			colors.append(Palette.DIGITS[i])
			offsets.append(float(i) / Palette.DIGITS.size())
		colors.append(Palette.WILD)
		offsets.append(0.95)
		_rainbow.offsets = offsets
		_rainbow.colors = colors
	return _rainbow
