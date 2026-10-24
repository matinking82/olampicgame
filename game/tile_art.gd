class_name TileArt
extends RefCounted
## Shared meshes, materials and font, built once in code (no imported assets).

const TILE_SIZE := 0.9
const TILE_HEIGHT := 0.42
const TILE_RADIUS := 0.16
const TILE_SHADER := preload("res://game/shaders/tile.gdshader")

static var _tile_mesh: ArrayMesh
static var _materials := {}
static var _ghosts := {}
static var _dim: StandardMaterial3D
static var _highlight: StandardMaterial3D
static var _font: Font


static func tile_mesh() -> ArrayMesh:
	if _tile_mesh == null:
		_tile_mesh = rounded_box(Vector3(TILE_SIZE, TILE_HEIGHT, TILE_SIZE), TILE_RADIUS)
	return _tile_mesh


## A box with rounded edges and corners. A subdivided cube is pulled
## outward around a smaller inner box, which rounds every edge by `radius`.
static func rounded_box(size: Vector3, radius: float, segments: int = 4) -> ArrayMesh:
	var n := segments * 2 + 2
	var box := BoxMesh.new()
	box.size = size
	box.subdivide_width = n - 1
	box.subdivide_height = n - 1
	box.subdivide_depth = n - 1
	var arrays := box.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var half := size * 0.5
	var inner := half - Vector3.ONE * radius
	for i in verts.size():
		var p := verts[i]
		for a in 3:
			p[a] = _spread(p[a], half[a], inner[a], n, segments)
		var core := p.clamp(-inner, inner)
		var out := p - core
		var nrm := out.normalized() if out.length_squared() > 1e-10 else normals[i]
		verts[i] = core + nrm * radius
		normals[i] = nrm
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Moves an evenly spaced grid coordinate so `k` of the `n` segments land on
## each rounded edge and the rest stay flat in the middle.
static func _spread(x: float, half: float, inner: float, n: int, k: int) -> float:
	var f := (x / half + 1.0) * 0.5 * n
	if f <= k:
		return -half + (f / k) * (half - inner)
	if f >= n - k:
		return half - ((n - f) / k) * (half - inner)
	return -inner + (f - k) / (n - 2 * k) * 2.0 * inner


## Candy shader for digits and wilds (wilds cycle through the rainbow);
## stones get a plain matte material so they read as dead weight.
static func material(v: int) -> Material:
	if not _materials.has(v):
		if Board.is_stone(v):
			var stone := StandardMaterial3D.new()
			stone.albedo_color = Palette.tile(v)
			stone.roughness = 0.75
			stone.rim_enabled = true
			stone.rim = 0.2
			_materials[v] = stone
		else:
			var m := ShaderMaterial.new()
			m.shader = TILE_SHADER
			m.set_shader_parameter("tile_color", Palette.tile(v))
			m.set_shader_parameter("rainbow", 1.0 if v == Board.WILD else 0.0)
			m.set_shader_parameter("half_height", TILE_HEIGHT * 0.5)
			m.set_shader_parameter("half_size", TILE_SIZE * 0.5)
			_materials[v] = m
	return _materials[v]


## See-through tile showing where a piece will land; red when it can't.
static func ghost_material(v: int, valid: bool) -> StandardMaterial3D:
	var key := v if valid else -1
	if not _ghosts.has(key):
		var c := Palette.tile(key)
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(c, 0.42)
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.9 if valid else 1.2
		m.roughness = 0.2
		_ghosts[key] = m
	return _ghosts[key]


static func dim_material() -> StandardMaterial3D:
	if _dim == null:
		_dim = StandardMaterial3D.new()
		_dim.albedo_color = Palette.DIM
		_dim.roughness = 0.6
	return _dim


## Additive white overlay for tiles a placement would clear. Pulsed by BoardView.
static func highlight_material() -> StandardMaterial3D:
	if _highlight == null:
		_highlight = StandardMaterial3D.new()
		_highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_highlight.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_highlight.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_highlight.albedo_color = Color(1, 1, 1, 0.4)
	return _highlight


static func glyph(v: int) -> String:
	if Board.is_digit(v):
		return str(v)
	match v:
		Board.WILD:
			return "★"
		Board.STONE_CRACKED:
			return "×"
	return ""


static func font() -> Font:
	if _font == null:
		var system := SystemFont.new()
		system.font_names = PackedStringArray(["Segoe UI", "Roboto", "Noto Sans", "sans-serif"])
		system.font_weight = 800
		# Thicken it a little more: chunky numbers read better on candy.
		var thick := FontVariation.new()
		thick.base_font = system
		thick.variation_embolden = 0.45
		_font = thick
	return _font
