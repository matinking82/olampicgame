class_name FlipArt
extends RefCounted
## Flip Four's look, built in code: the two-sided candy disc, the gold ring
## of a locked disc, and the team colours. Side 0 is the warm Sun team,
## side 1 the cool Ice team, as in the other versus games. Discs stand up
## in the rack facing the player: Sun's face forward, or turned round for
## Ice.

const DISC_SHADER := preload("res://flip/shaders/disc.gdshader")
const RADIUS := 0.38
const HALF := 0.075

const COLORS := [Color("ffae1f"), Color("22c8ff")]
const TEAM_NAMES := ["SUN", "ICE"]
## Bright team colours for UI text (shared with the other versus games).
const TEAM_UI := [Color("ffc61a"), Color("39e0ff")]

static var _mesh: ArrayMesh
static var _material: ShaderMaterial
static var _ring: TorusMesh


static func team_color(side: int) -> Color:
	return TEAM_UI[side]


## A rounded disc lathed from its profile, centred on its middle.
static func disc_mesh() -> ArrayMesh:
	if _mesh == null:
		var r := RADIUS
		var h := HALF
		_mesh = BoardKit.lathe([Vector2(0, -h), Vector2(r - 0.05, -h), Vector2(r - 0.015, -h + 0.012),
			Vector2(r, -h + 0.04), Vector2(r, h - 0.04), Vector2(r - 0.015, h - 0.012),
			Vector2(r - 0.05, h), Vector2(0, h)], 40)
	return _mesh


static func disc_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = DISC_SHADER
		_material.set_shader_parameter("top_color", COLORS[0])
		_material.set_shader_parameter("bottom_color", COLORS[1])
	return _material


## The body's turn that shows `side` toward the camera (+Z).
static func face_basis(side: int) -> Basis:
	var up := Basis(Vector3.RIGHT, PI * 0.5)
	return up if side == 0 else Basis(Vector3.UP, PI) * up


static func ring_mesh() -> TorusMesh:
	if _ring == null:
		_ring = TorusMesh.new()
		_ring.inner_radius = RADIUS - 0.07
		_ring.outer_radius = RADIUS + 0.05
		_ring.rings = 40
		_ring.ring_segments = 10
	return _ring
