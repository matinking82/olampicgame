class_name Feel
extends Node
## Turns impacts into camera shake, hit-stop and phone vibration, all
## respecting the player's settings.

## Camera shake: max offset in world units, and how fast trauma fades per second.
const SHAKE_OFFSET := 0.45
const SHAKE_DECAY := 1.8
## Impacts at least this strong freeze the game for a moment.
const HIT_STOP_FROM := 0.55

var camera: Camera3D
## Normal game speed; hit-stop returns to this. Raised by the dev tools to
## fast-forward autoplay.
var time_scale := 1.0
var _trauma := 0.0
var _hit_stops := 0


func _init(cam: Camera3D = null) -> void:
	camera = cam


## How hard something hit, 0-1.
func impact(strength: float) -> void:
	if Settings.screen_shake:
		_trauma = minf(1.0, _trauma + strength * 0.8)
	if strength >= HIT_STOP_FROM:
		hit_stop(0.04 + 0.06 * strength)
	if Settings.vibration and OS.has_feature("mobile"):
		Input.vibrate_handheld(roundi(10 + 50 * strength))


## Squared trauma gives small knocks a light touch and big hits a real jolt.
func _process(delta: float) -> void:
	if camera == null:
		return
	_trauma = maxf(0.0, _trauma - SHAKE_DECAY * delta)
	var amount := _trauma * _trauma * SHAKE_OFFSET
	var t := Time.get_ticks_msec() * 0.001
	camera.h_offset = amount * sin(t * 47.0)
	camera.v_offset = amount * sin(t * 59.0 + 1.7)


## Freezes the game for a split second so a big hit lands with weight.
## Tweens and timers pause with it; the real-time timer brings it back.
func hit_stop(duration: float) -> void:
	_hit_stops += 1
	Engine.time_scale = 0.02
	await get_tree().create_timer(duration, true, false, true).timeout
	_hit_stops -= 1
	if _hit_stops == 0:
		Engine.time_scale = time_scale


func set_time_scale(v: float) -> void:
	time_scale = v
	Engine.time_scale = v
