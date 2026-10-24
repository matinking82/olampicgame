class_name ChessArt
extends RefCounted
## Merge Mate's look, built in code: lathed candy chess pieces (the knight's
## head is an extruded silhouette), their materials and the team colours.
## Side 0 is the warm Sun team, side 1 the cool Ice team; within a team
## each tier has its own colour, so upgrades are easy to see.

const R := preload("res://chess/chess_rules.gd")
const PIECE_SHADER := preload("res://chess/shaders/piece.gdshader")
const SEGMENTS := 28

## Colours by side, then by type (index = type).
const COLORS := [
	[Color.BLACK, Color("ffc61a"), Color("ff8a1f"), Color("ff7a2f"), Color("ff3b5c"),
		Color("ff4fcf"), Color("ffb0e0"), Color("ffe04d")],
	[Color.BLACK, Color("22e0a8"), Color("1fc8e0"), Color("1fb0f0"), Color("3d82ff"),
		Color("8f5bff"), Color("b0a0ff"), Color("8fe8ff")],
]
const TRIM := [Color("ffd21f"), Color("39f0ff")]
const TEAM_NAMES := ["SUN", "ICE"]
## Bright team colours for UI text.
const TEAM_UI := [Color("ffc61a"), Color("39e0ff")]

static var _meshes := {}
static var _materials := {}


static func color(p: int) -> Color:
	return COLORS[R.side_of(p)][R.type_of(p)]


static func team_color(side: int) -> Color:
	return TEAM_UI[side]


static func height(type: int) -> float:
	return [0.0, 0.7, 0.98, 1.02, 0.92, 1.12, 1.18, 1.26][type]


static func mesh(type: int) -> ArrayMesh:
	if not _meshes.has(type):
		_meshes[type] = _build(type)
	return _meshes[type]


static func material(p: int) -> ShaderMaterial:
	if not _materials.has(p):
		var m := ShaderMaterial.new()
		m.shader = PIECE_SHADER
		m.set_shader_parameter("piece_color", color(p))
		m.set_shader_parameter("trim_color", TRIM[R.side_of(p)])
		m.set_shader_parameter("height", height(R.type_of(p)))
		m.set_shader_parameter("rainbow", 0.85 if R.type_of(p) == R.EMPRESS else 0.0)
		_materials[p] = m
	return _materials[p]


# --- Meshes ----------------------------------------------------------------------

## The foot every piece stands on: a rounded disc with a lip.
const FOOT := [Vector2(0.0, 0.0), Vector2(0.34, 0.0), Vector2(0.37, 0.03), Vector2(0.37, 0.07),
	Vector2(0.34, 0.11), Vector2(0.29, 0.13), Vector2(0.27, 0.16)]


static func _build(type: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	match type:
		R.PAWN:
			_lathe(st, FOOT + [Vector2(0.2, 0.2), Vector2(0.13, 0.33), Vector2(0.11, 0.4),
				Vector2(0.19, 0.42), Vector2(0.19, 0.45), Vector2(0.1, 0.47)] + _arc(0.58, 0.14, -60.0))
		R.KNIGHT:
			_lathe(st, FOOT + [Vector2(0.24, 0.2), Vector2(0.22, 0.24), Vector2(0.0, 0.24)])
			_knight_head(st)
		R.BISHOP:
			_lathe(st, FOOT + [Vector2(0.19, 0.22), Vector2(0.12, 0.4), Vector2(0.1, 0.5),
				Vector2(0.2, 0.53), Vector2(0.2, 0.57), Vector2(0.11, 0.6), Vector2(0.15, 0.64),
				Vector2(0.19, 0.7), Vector2(0.2, 0.76), Vector2(0.18, 0.83), Vector2(0.13, 0.9),
				Vector2(0.07, 0.96), Vector2(0.025, 1.0)] + _arc(1.03, 0.045, -40.0))
			_ring(st, 0.79, 0.19, 0.022)
		R.ROOK:
			_lathe(st, FOOT + [Vector2(0.25, 0.2), Vector2(0.21, 0.35), Vector2(0.2, 0.6),
				Vector2(0.27, 0.66), Vector2(0.28, 0.82), Vector2(0.18, 0.82), Vector2(0.18, 0.78), Vector2(0.0, 0.78)])
			for i in 4:
				var a := TAU * i / 4.0 + PI / 4.0
				_box(st, Vector3(cos(a) * 0.235, 0.86, sin(a) * 0.235), Vector3(0.1, 0.1, 0.1), a)
		R.QUEEN, R.EMPRESS:
			var tall := 0.06 if type == R.EMPRESS else 0.0
			_lathe(st, FOOT + [Vector2(0.21, 0.24), Vector2(0.13, 0.5), Vector2(0.12, 0.64 + tall),
				Vector2(0.22, 0.68 + tall), Vector2(0.22, 0.72 + tall), Vector2(0.14, 0.75 + tall),
				Vector2(0.17, 0.84 + tall), Vector2(0.26, 0.96 + tall), Vector2(0.2, 0.96 + tall),
				Vector2(0.12, 0.99 + tall), Vector2(0.04, 1.02 + tall)] + _arc(1.06 + tall, 0.06, -30.0))
			for i in 8:
				var a := TAU * i / 8.0
				_sphere(st, Vector3(cos(a) * 0.245, 0.97 + tall, sin(a) * 0.245), 0.045)
			if type == R.EMPRESS:
				_ring(st, 1.22, 0.3, 0.03)
		R.KING:
			_lathe(st, FOOT + [Vector2(0.22, 0.24), Vector2(0.14, 0.52), Vector2(0.13, 0.7),
				Vector2(0.23, 0.74), Vector2(0.23, 0.78), Vector2(0.15, 0.81), Vector2(0.2, 0.92),
				Vector2(0.22, 0.98), Vector2(0.16, 1.03), Vector2(0.05, 1.06), Vector2(0.0, 1.06)])
			_box(st, Vector3(0, 1.15, 0), Vector3(0.07, 0.24, 0.07), 0.0)
			_box(st, Vector3(0, 1.17, 0), Vector3(0.2, 0.07, 0.07), 0.0)
	st.generate_normals()
	return st.commit()


## Points along the top of a ball (for pawn heads and finials), from
## `start_deg` (below the equator) round to the top.
static func _arc(center_y: float, radius: float, start_deg: float) -> Array:
	var pts := []
	for i in 9:
		var a := deg_to_rad(lerpf(start_deg, 90.0, i / 8.0))
		pts.append(Vector2(cos(a) * radius, center_y + sin(a) * radius))
	pts[pts.size() - 1] = Vector2(0.0, center_y + radius)
	return pts


## Spins a profile (x = radius, y = height) round the Y axis.
static func _lathe(st: SurfaceTool, profile: Array) -> void:
	for i in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		for s in SEGMENTS:
			var t0 := TAU * s / SEGMENTS
			var t1 := TAU * (s + 1) / SEGMENTS
			var p00 := Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x)
			var p01 := Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x)
			var p10 := Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)
			var p11 := Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x)
			_quad(st, p00, p01, p11, p10)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v: Vector3 in [a, b, c, a, c, d]:
		st.add_vertex(v)


static func _box(st: SurfaceTool, center: Vector3, size: Vector3, angle: float) -> void:
	var box := BoxMesh.new()
	box.size = size
	_append(st, box, Transform3D(Basis(Vector3.UP, -angle), center))


static func _sphere(st: SurfaceTool, center: Vector3, radius: float) -> void:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 10
	s.rings = 5
	_append(st, s, Transform3D(Basis(), center))


static func _ring(st: SurfaceTool, y: float, radius: float, thickness: float) -> void:
	var t := TorusMesh.new()
	t.inner_radius = radius - thickness
	t.outer_radius = radius + thickness
	t.rings = 32
	t.ring_segments = 8
	_append(st, t, Transform3D(Basis(), Vector3(0, y, 0)))


## Copies a primitive's triangles in as plain vertices (SurfaceTool's own
## append_from would switch the surface to indexed and drop what's there).
static func _append(st: SurfaceTool, primitive: PrimitiveMesh, xf: Transform3D) -> void:
	var arrays := primitive.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in indices:
		st.add_vertex(xf * verts[i])


## The horse head: a side-on silhouette extruded to a slab, facing +Z (the
## view turns it to face the enemy).
static func _knight_head(st: SurfaceTool) -> void:
	var outline := PackedVector2Array([
		Vector2(-0.22, 0.22), Vector2(0.2, 0.22), Vector2(0.17, 0.36), Vector2(0.09, 0.46),
		Vector2(0.3, 0.62), Vector2(0.35, 0.7), Vector2(0.33, 0.79), Vector2(0.24, 0.83),
		Vector2(0.12, 0.89), Vector2(0.09, 0.99), Vector2(0.02, 0.93), Vector2(-0.05, 1.01),
		Vector2(-0.1, 0.88), Vector2(-0.2, 0.74), Vector2(-0.25, 0.55), Vector2(-0.26, 0.36),
	])
	var depth := 0.11
	var tris := Geometry2D.triangulate_polygon(outline)
	# Faces: x across the head, y up, z = the silhouette's x (forward).
	for side: float in [-1.0, 1.0]:
		for i in range(0, tris.size(), 3):
			var idx := [tris[i], tris[i + 1], tris[i + 2]]
			if side < 0:
				idx.reverse()
			for k: int in idx:
				var p := outline[k]
				st.add_vertex(Vector3(depth * side, p.y, p.x))
	var n := outline.size()
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		_quad(st, Vector3(depth, a.y, a.x), Vector3(-depth, a.y, a.x), Vector3(-depth, b.y, b.x), Vector3(depth, b.y, b.x))
	# Eyes.
	for side: float in [-1.0, 1.0]:
		_sphere(st, Vector3(depth * side, 0.8, 0.14), 0.035)
