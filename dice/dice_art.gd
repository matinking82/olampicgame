class_name DiceArt
extends RefCounted
## Tic Tac Roll's look, built in code: candy dice, the X and O marks, the
## team colours, and the colour and label of each category's cell. Side 0
## is the warm Sun team (X), side 1 the cool Ice team (O), as in Merge Mate.

const R := preload("res://dice/dice_rules.gd")
const DIE_SHADER := preload("res://dice/shaders/die.gdshader")
const MARK_SHADER := preload("res://dice/shaders/mark.gdshader")
const DIE_SIZE := 0.72
const MARK_HEIGHT := 0.22

const DIE_COLORS := [Color("ff9a1f"), Color("1fb4f0")]
const MARK_COLORS := [Color("ffb81f"), Color("2ad8ff")]
const TEAM_NAMES := ["SUN", "ICE"]
## Bright team colours for UI text (the same as Merge Mate's).
const TEAM_UI := [Color("ffc61a"), Color("39e0ff")]
## Face-count cells share one cool colour; each combo has its own.
const UPPER_COLOR := Color("b9c2ff")
const CAT_COLORS := {
	R.Cat.CHANCE: Color("d6b8ff"), R.Cat.TWO_PAIRS: Color("5ce6a6"), R.Cat.THREE_KIND: Color("ff9a3c"),
	R.Cat.FOUR_KIND: Color("ff4f6e"), R.Cat.FULL_HOUSE: Color("ff5fd2"), R.Cat.SMALL_STRAIGHT: Color("3fd8f0"),
	R.Cat.BIG_STRAIGHT: Color("5b8cff"), R.Cat.FIVE_KIND: Color("ffd21f"),
}
## Text printed on each cell, and the small line under it.
const CAT_LABELS := {
	R.Cat.CHANCE: "CHANCE", R.Cat.TWO_PAIRS: "TWO\nPAIRS", R.Cat.THREE_KIND: "3 OF A\nKIND",
	R.Cat.FOUR_KIND: "4 OF A\nKIND", R.Cat.FULL_HOUSE: "FULL\nHOUSE", R.Cat.SMALL_STRAIGHT: "SMALL\nSTRAIGHT",
	R.Cat.BIG_STRAIGHT: "BIG\nSTRAIGHT", R.Cat.FIVE_KIND: "5 OF A\nKIND",
}

static var _die_mesh: ArrayMesh
static var _die_materials := {}
static var _mark_materials := {}
static var _bar_mesh: ArrayMesh
static var _ring_mesh: TorusMesh


static func team_color(side: int) -> Color:
	return TEAM_UI[side]


static func cat_color(cat: int) -> Color:
	return UPPER_COLOR if R.is_upper(cat) else CAT_COLORS[cat]


static func cat_label(cat: int) -> String:
	return "%ds" % (cat + 1) if R.is_upper(cat) else CAT_LABELS[cat]


## The small print under a category: what it scores.
static func cat_rule(cat: int) -> String:
	if R.is_upper(cat):
		return "2 OR MORE"
	if R.FIXED.has(cat):
		return "%d PTS" % R.FIXED[cat]
	return "SUM"


static func die_mesh() -> ArrayMesh:
	if _die_mesh == null:
		_die_mesh = TileArt.rounded_box(Vector3.ONE * DIE_SIZE, 0.12)
	return _die_mesh


## Die material per side (0, 1), or -1 for the plain white dice on cells.
static func die_material(side: int) -> ShaderMaterial:
	if not _die_materials.has(side):
		var m := ShaderMaterial.new()
		m.shader = DIE_SHADER
		m.set_shader_parameter("half_size", DIE_SIZE * 0.5)
		if side < 0:
			m.set_shader_parameter("die_color", Color("f4f0ff"))
			m.set_shader_parameter("pip_color", Color("3a2a8a"))
		else:
			m.set_shader_parameter("die_color", DIE_COLORS[side])
			m.set_shader_parameter("pip_color", Color.WHITE)
		_die_materials[side] = m
	return _die_materials[side]


## The fever version cycles through the rainbow.
static func fever_die_material(side: int) -> ShaderMaterial:
	var key := side + 10
	if not _die_materials.has(key):
		var m: ShaderMaterial = die_material(side).duplicate()
		m.set_shader_parameter("rainbow", 0.8)
		_die_materials[key] = m
	return _die_materials[key]


## Turns a die so face `v` points up, then spins it `yaw` around upright.
static func face_basis(v: int, yaw: float = 0.0) -> Basis:
	var b := Basis.IDENTITY
	match v:
		2:
			b = Basis(Vector3.BACK, PI * 0.5)
		3:
			b = Basis(Vector3.RIGHT, -PI * 0.5)
		4:
			b = Basis(Vector3.RIGHT, PI * 0.5)
		5:
			b = Basis(Vector3.BACK, -PI * 0.5)
		6:
			b = Basis(Vector3.RIGHT, PI)
	return Basis(Vector3.UP, yaw) * b


static func mark_material(side: int) -> ShaderMaterial:
	if not _mark_materials.has(side):
		var m := ShaderMaterial.new()
		m.shader = MARK_SHADER
		m.set_shader_parameter("mark_color", MARK_COLORS[side])
		m.set_shader_parameter("half_height", MARK_HEIGHT * 0.5)
		_mark_materials[side] = m
	return _mark_materials[side]


## One bar of the X.
static func bar_mesh() -> ArrayMesh:
	if _bar_mesh == null:
		_bar_mesh = TileArt.rounded_box(Vector3(0.86, MARK_HEIGHT, 0.22), 0.1)
	return _bar_mesh


## The O.
static func ring_mesh() -> TorusMesh:
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.16
		_ring_mesh.outer_radius = 0.16 + MARK_HEIGHT + 0.01
		_ring_mesh.rings = 48
		_ring_mesh.ring_segments = 20
	return _ring_mesh
