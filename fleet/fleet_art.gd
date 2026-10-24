class_name FleetArt
extends RefCounted
## Mine Fleet's look, built in code: the candy covers over unknown sea,
## open water, the number colours, candy ships, hit pegs and flags. Side 0
## is the warm Sun navy, side 1 the cool Ice navy.

const CELL := 1.0
const COVER_HEIGHT := 0.26
const SHIP_HEIGHT := 0.34

const SHIP_COLORS := [Color("ff9a1f"), Color("1fb4f0")]
const TEAM_NAMES := ["SUN", "ICE"]
## Bright team colours for UI text (shared with the other versus games).
const TEAM_UI := [Color("ffc61a"), Color("39e0ff")]
const COVER := Color("7d6cf0")
const COVER_ALT := Color("8f7ff7")
const WATER := Color("163a7a")
const WATER_ALT := Color("1a4388")
const HIT := Color("ff3b5c")
const FLAG := Color("ff4fcf")
## Number colours, 1 up to 8 (Minesweeper-style, candy-bright).
const NUMBERS := [Color.WHITE, Color("39e0ff"), Color("5ce6a6"), Color("ffd21f"), Color("ff9a3c"),
	Color("ff4f6e"), Color("ff4fcf"), Color("c9a8ff"), Color.WHITE]

static var _cover_mesh: ArrayMesh
static var _ship_meshes := {}


static func team_color(side: int) -> Color:
	return TEAM_UI[side]


static func number_color(v: int) -> Color:
	return NUMBERS[clampi(v, 0, 8)]


static func cover_mesh() -> ArrayMesh:
	if _cover_mesh == null:
		_cover_mesh = TileArt.rounded_box(Vector3(CELL * 0.9, COVER_HEIGHT, CELL * 0.9), 0.12)
	return _cover_mesh


## A candy boat `length` squares long, lying along +X from its centre: a
## rounded hull with a cabin and a funnel on deck.
static func ship(length: int, side: int) -> Node3D:
	var root := Node3D.new()
	var mat := BoardKit.candy(SHIP_COLORS[side], SHIP_HEIGHT)
	var hull := MeshInstance3D.new()
	if not _ship_meshes.has(length):
		_ship_meshes[length] = TileArt.rounded_box(Vector3(length * CELL - 0.16, SHIP_HEIGHT, CELL * 0.62), 0.15)
	hull.mesh = _ship_meshes[length]
	hull.position.y = SHIP_HEIGHT * 0.5
	hull.material_override = mat
	root.add_child(hull)
	var deck := BoardKit.candy(Color.WHITE.lerp(SHIP_COLORS[side], 0.25), 0.3)
	var cabin := MeshInstance3D.new()
	cabin.mesh = TileArt.rounded_box(Vector3(minf(0.5, length * 0.3), 0.22, 0.36), 0.06)
	cabin.position = Vector3(-0.1 * (length - 1), SHIP_HEIGHT + 0.11, 0)
	cabin.material_override = deck
	root.add_child(cabin)
	var funnel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.1
	cyl.height = 0.24
	funnel.mesh = cyl
	funnel.position = Vector3(-0.1 * (length - 1) + 0.12, SHIP_HEIGHT + 0.3, 0)
	funnel.material_override = BoardKit.candy(Palette.HOT, 0.24)
	root.add_child(funnel)
	return root


## The peg left in a hit square: a glowing red candy ball.
static func hit_peg() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.2
	s.height = 0.4
	m.mesh = s
	m.material_override = BoardKit.candy(HIT, 0.4)
	m.set_instance_shader_parameter("glow", 1.2)
	return m


## A little pink pennant on a stick, for a flagged square.
static func flag() -> Node3D:
	var root := Node3D.new()
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = 0.6
	pole.mesh = cyl
	pole.position.y = 0.3
	pole.material_override = BoardKit.candy(Color.WHITE, 0.6)
	root.add_child(pole)
	var pennant := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.3, 0.32, 0.04)
	pennant.mesh = prism
	pennant.rotation.z = -PI * 0.5
	pennant.position = Vector3(0.16, 0.45, 0)
	pennant.material_override = BoardKit.candy(FLAG, 0.3)
	root.add_child(pennant)
	return root
