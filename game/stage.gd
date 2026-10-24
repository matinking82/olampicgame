class_name Stage
extends RefCounted
## The shared world every scene stands in: the animated gradient backdrop,
## glow and colour grading, the sun, and a camera that frames whatever
## matters inside the part of the screen the HUD leaves free.

const BACKGROUND_LAYER := -10
const BACKGROUND_SHADER := preload("res://game/shaders/background.gdshader")
const CAMERA_FOV := 34.0
const PORTRAIT_UI_SCALE := 1.6


## Adds the environment, backdrop, sun and camera under `parent`.
## Returns {"camera": Camera3D, "background": ShaderMaterial}.
static func build(parent: Node) -> Dictionary:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("5b46c9")
	sky_mat.sky_horizon_color = Color("ffb3d9")
	sky_mat.ground_horizon_color = Color("ff9ccf")
	sky_mat.ground_bottom_color = Color("2a1866")
	sky_mat.ground_curve = 0.06
	var sky := Sky.new()
	sky.sky_material = sky_mat

	# The 3D view draws over an animated 2D gradient (BG_CANVAS); the sky is
	# still used for ambient light and reflections on the glossy pieces.
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = BACKGROUND_LAYER
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Linear tone mapping keeps the candy colours saturated; only the
	# brightest highlights are allowed to bloom.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.08
	var world := WorldEnvironment.new()
	world.environment = env
	parent.add_child(world)

	var backdrop := CanvasLayer.new()
	backdrop.layer = BACKGROUND_LAYER
	var gradient := ColorRect.new()
	gradient.set_anchors_preset(Control.PRESET_FULL_RECT)
	gradient.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := ShaderMaterial.new()
	background.shader = BACKGROUND_SHADER
	gradient.material = background
	backdrop.add_child(gradient)
	parent.add_child(backdrop)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	parent.add_child(sun)

	var camera := Camera3D.new()
	camera.fov = CAMERA_FOV
	parent.add_child(camera)
	camera.make_current()
	return {"camera": camera, "background": background}


## The UI is designed for a 1280x720 landscape screen; on tall screens it
## would shrink to fit the narrow width, so scale it back up. Returns true
## for portrait.
static func fit_ui(window: Window) -> bool:
	var size := Vector2(window.size)
	var portrait := size.y > size.x * 1.05
	var ui_scale := PORTRAIT_UI_SCALE if portrait else 1.0
	if not is_equal_approx(window.content_scale_factor, ui_scale):
		window.content_scale_factor = ui_scale
	return portrait


## Backs the camera off until the box lo..hi fits the free rectangle of the
## screen, then slides it sideways so the box sits centred in it. `yaw`
## turns the view around the board (180 looks from the far side).
static func fit_camera(camera: Camera3D, lo: Vector3, hi: Vector3, free: Rect2, size: Vector2,
		pitch_deg: float, yaw_deg: float = 0.0) -> void:
	var center := (lo + hi) * 0.5
	var pitch := deg_to_rad(pitch_deg)
	var back := Vector3(0, sin(pitch), cos(pitch)).rotated(Vector3.UP, deg_to_rad(yaw_deg))
	var corners: Array[Vector3] = []
	for x: float in [lo.x, hi.x]:
		for y: float in [lo.y, hi.y]:
			for z: float in [lo.z, hi.z]:
				corners.append(Vector3(x, y, z))
	var near := 4.0
	var far := 150.0
	for i in 24:
		var mid := (near + far) * 0.5
		_aim(camera, center, back, mid)
		var rect := _screen_rect(camera, corners)
		if rect.size.x <= free.size.x and rect.size.y <= free.size.y:
			far = mid
		else:
			near = mid
	_aim(camera, center, back, far)
	var world_per_px := 2.0 * far * tan(deg_to_rad(camera.fov) * 0.5) / size.y
	for i in 3:
		var shift := free.get_center() - _screen_rect(camera, corners).get_center()
		camera.position -= camera.global_basis.x * shift.x * world_per_px
		camera.position += camera.global_basis.y * shift.y * world_per_px


static func _aim(camera: Camera3D, center: Vector3, back: Vector3, distance: float) -> void:
	camera.position = center + back * distance
	camera.look_at(center, Vector3.UP)


static func _screen_rect(camera: Camera3D, points: Array[Vector3]) -> Rect2:
	var rect := Rect2(camera.unproject_position(points[0]), Vector2.ZERO)
	for p in points:
		rect = rect.expand(camera.unproject_position(p))
	return rect


static func pointer_on_plane(camera: Camera3D, screen: Vector2, height: float) -> Vector3:
	var hit: Variant = Plane(Vector3.UP, height).intersects_ray(
		camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	return hit if hit != null else Vector3.ZERO
