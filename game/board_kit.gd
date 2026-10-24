class_name BoardKit
extends RefCounted
## Shared 3D bits for the board games: glossy and glowing materials, flat
## and floating labels, the neon-framed candy slab, tutorial arrows, rings
## and outlines. Everything is built in code, like the rest of the art.

const NEON_SHADER := preload("res://game/shaders/neon_frame.gdshader")
const CELL_SHADER := preload("res://game/shaders/cell.gdshader")
const CANDY_SHADER := preload("res://dice/shaders/mark.gdshader")

static var _candy := {}


static func glossy(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.12
	m.metallic = 0.3
	m.clearcoat_enabled = true
	m.rim_enabled = true
	m.rim = 0.4
	return m


static func unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	return m


## A glossy candy material that darkens toward the foot of a piece `height`
## tall, with glow / flash / dim instance uniforms (the X and O shader).
static func candy(c: Color, height: float) -> ShaderMaterial:
	var key := "%s/%.3f" % [c.to_html(), height]
	if not _candy.has(key):
		var m := ShaderMaterial.new()
		m.shader = CANDY_SHADER
		m.set_shader_parameter("mark_color", c)
		m.set_shader_parameter("half_height", height * 0.5)
		_candy[key] = m
	return _candy[key]


## A board cell tile: a rounded square cut from a plane.
static func cell_material(c: Color, corner: float = 0.14) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CELL_SHADER
	m.set_shader_parameter("cell_color", c)
	m.set_shader_parameter("corner", corner)
	return m


## Text printed flat on the board, facing up.
static func flat_label(size: int) -> Label3D:
	var l := Label3D.new()
	l.font = TileArt.font()
	l.font_size = size
	l.pixel_size = 0.0045
	l.outline_size = 14
	l.outline_modulate = Palette.INK
	l.line_spacing = -10
	l.rotation_degrees.x = -90.0
	return l


## Text that always faces the camera and draws over everything.
static func billboard(text: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = TileArt.font()
	l.font_size = size
	l.pixel_size = 0.005
	l.outline_size = 26
	l.outline_modulate = Palette.INK
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	return l


## The board's base: a rainbow neon frame round a glossy slab, `size` wide
## and deep, centred on `center`. Returns [root, frame material].
static func base(size: Vector2, center: Vector3 = Vector3.ZERO) -> Array:
	var root := Node3D.new()
	root.position = center
	var frame := MeshInstance3D.new()
	frame.mesh = TileArt.rounded_box(Vector3(size.x + 0.3, 0.4, size.y + 0.3), 0.2)
	frame.position.y = -0.34
	var frame_mat := ShaderMaterial.new()
	frame_mat.shader = NEON_SHADER
	frame.material_override = frame_mat
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(frame)
	var slab := MeshInstance3D.new()
	slab.mesh = TileArt.rounded_box(Vector3(size.x, 0.6, size.y), 0.25)
	slab.position.y = -0.3
	slab.material_override = glossy(Palette.BOARD)
	root.add_child(slab)
	return [root, frame_mat]


## A bouncing gold cone for the tutorial to point with.
static func arrow() -> MeshInstance3D:
	var arrow := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.22
	cone.bottom_radius = 0.0
	cone.height = 0.45
	arrow.mesh = cone
	arrow.material_override = unshaded(Color(2.4, 2.0, 0.4))
	return arrow


## A thin flat glowing ring.
static func ring(c: Color, radius: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.06
	torus.outer_radius = radius
	torus.rings = 32
	torus.ring_segments = 6
	m.mesh = torus
	m.scale = Vector3(1, 0.3, 1)
	m.material_override = unshaded(c)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## A thin glowing square border, lying flat.
static func outline(c: Color, size: float) -> Node3D:
	var frame := Node3D.new()
	var mat := unshaded(c)
	for k in 4:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(size, 0.02, 0.05)
		bar.mesh = box
		bar.material_override = mat
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bar.rotation.y = PI * 0.5 * k
		bar.position = Vector3(0, 0, size * 0.5 - 0.025).rotated(Vector3.UP, PI * 0.5 * k)
		frame.add_child(bar)
	return frame


static func flat_square(c: Color, size: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	m.mesh = plane
	m.material_override = unshaded(c)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## A small glowing dot lying on the board (legal-move markers).
static func dot(c: Color, radius: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.02
	cyl.radial_segments = 24
	cyl.rings = 1
	m.mesh = cyl
	m.material_override = unshaded(c)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## Spins a profile (x = radius, y = height) round the Y axis into a smooth
## mesh. The profile runs from the bottom centre outward and up, like the
## chess pieces'.
static func lathe(profile: Array, segments: int = 28) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for i in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		for s in segments:
			var t0 := TAU * s / segments
			var t1 := TAU * (s + 1) / segments
			var p00 := Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x)
			var p01 := Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x)
			var p10 := Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)
			var p11 := Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x)
			for v: Vector3 in [p00, p01, p11, p00, p11, p10]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## A label that rises from a point and fades out.
static func float_text(parent: Node3D, text: String, at: Vector3, color: Color, size: int = 110) -> void:
	var l := billboard(text, size, color)
	l.render_priority = 10
	l.position = at + Vector3(0, 1.3, 0)
	parent.add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", at.y + 2.9, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tw.chain().tween_callback(l.queue_free)
