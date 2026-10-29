class_name TrayView
extends Node3D
## The three tray slots. Pieces sit here shrunk down; dragging lifts a
## piece out (take_node) and a failed drop sends it back (return_node).

const SPACING := 3.3
const PIECE_SCALE := 0.6
const PICK_RADIUS := 1.65

## PieceNode or null per slot.
var nodes: Array = [null, null, null]
var vertical := false
var _pads: Array[MeshInstance3D] = []


func _ready() -> void:
	# Frosted glass pads with a soft glowing edge underneath.
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Palette.PAD
	pad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pad_mat.roughness = 0.1
	pad_mat.clearcoat_enabled = true
	pad_mat.rim_enabled = true
	pad_mat.rim = 0.5
	var edge_mat := StandardMaterial3D.new()
	edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	edge_mat.albedo_color = Color(Palette.LINE, 0.55)
	var pad_mesh := TileArt.rounded_box(Vector3(2.9, 0.16, 2.9), 0.07, 3)
	var edge_mesh := TileArt.rounded_box(Vector3(3.0, 0.06, 3.0), 0.03, 3)
	for i in 3:
		var pad := MeshInstance3D.new()
		pad.mesh = pad_mesh
		pad.material_override = pad_mat
		var edge := MeshInstance3D.new()
		edge.mesh = edge_mesh
		edge.material_override = edge_mat
		edge.position.y = -0.07
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pad.add_child(edge)
		add_child(pad)
		_pads.append(pad)
	set_vertical(false)


## Slots side by side (portrait screens) or stacked (landscape screens).
func set_vertical(v: bool) -> void:
	vertical = v
	for i in 3:
		_pads[i].position = slot_local(i) - Vector3(0, 0.1, 0)
		if nodes[i] != null:
			nodes[i].position = slot_local(i)


func slot_local(i: int) -> Vector3:
	var off := (i - 1) * SPACING
	return Vector3(0, 0, off) if vertical else Vector3(off, 0, 0)


## The slot under a point on the ground, or -1.
func slot_at(world: Vector3) -> int:
	var l := to_local(world)
	var flat := Vector2(l.x, l.z)
	for i in 3:
		var s := slot_local(i)
		if flat.distance_to(Vector2(s.x, s.z)) <= PICK_RADIUS:
			return i
	return -1


func show_tray(state: GameState, animate: bool) -> void:
	for i in 3:
		set_slot(i, state.piece(i), animate)


func set_slot(i: int, piece: Piece, animate: bool = false) -> PieceNode:
	if nodes[i] != null:
		nodes[i].queue_free()
		nodes[i] = null
	if piece == null:
		return null
	var n := PieceNode.new(piece)
	n.position = slot_local(i)
	n.scale = Vector3.ONE * PIECE_SCALE
	add_child(n)
	nodes[i] = n
	if animate:
		# Drop in from above one after another, landing with a bounce.
		n.scale = Vector3.ONE * 0.01
		n.position.y = 3.0
		n.rotation.y = randf_range(-0.6, 0.6)
		var delay := 0.09 * i
		Sound.play_later(delay + 0.12, "deal", 1.0 + 0.12 * i)
		var tw := n.create_tween().set_parallel(true)
		tw.tween_property(n, "scale", Vector3.ONE * PIECE_SCALE, 0.3).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(n, "position:y", 0.0, 0.45).set_delay(delay).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(n, "rotation:y", 0.0, 0.4).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return n


## Rebuilds a slot after a rotation and spins it into place.
func spin_slot(i: int, piece: Piece) -> void:
	var n := set_slot(i, piece)
	if n == null:
		return
	n.rotation.y = PI * 0.5
	n.create_tween().tween_property(n, "rotation:y", 0.0, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Detaches a slot's piece so it can be dragged around the scene.
func take_node(i: int) -> PieceNode:
	var n: PieceNode = nodes[i]
	nodes[i] = null
	n.reparent(get_parent())
	return n


func return_node(i: int, n: PieceNode) -> void:
	n.reparent(self)
	nodes[i] = n
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "position", slot_local(i), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "scale", Vector3.ONE * PIECE_SCALE, 0.22)
	tw.tween_property(n, "rotation", Vector3.ZERO, 0.22)


## Greys out pieces that can't go anywhere, even rotated.
func update_fit(state: GameState) -> void:
	for i in 3:
		if nodes[i] != null and state.piece(i) != null:
			nodes[i].set_dimmed(not Rules.fits_any_rotation(state.board, state.piece(i)))
