extends Node
## Autoload "Sound": plays effects from a pool of players, the climbing
## pentatonic pop notes, and three music layers that fade in with the streak.
## The sounds themselves are WAV files rendered by tools/make_audio.gd.

const SFX_DIR := "res://audio/sfx/"
const MUSIC_DIR := "res://audio/music/"
const NOTE_COUNT := 13
const VOICES := 24
## Per-effect volume trims in dB, so the mix sits right.
const TRIM := {
	"pickup": -10.0, "place": -4.0, "rotate": -12.0, "invalid": -8.0, "suck": -10.0,
	"blast": -2.0, "star": -2.0, "coin": -6.0, "level_up": -4.0, "perfect": -2.0,
	"fever": -5.0, "thud": -3.0, "crack": -8.0, "laser": -5.0, "bomb": -2.0,
	"nuke": -2.0, "hammer": -5.0, "game_over": -3.0, "click": -10.0, "deal": -14.0,
	"alarm": -8.0, "whoosh": -12.0,
	"move": -5.0, "capture": -3.0, "check": -7.0, "mate": -2.0, "drop": -9.0, "tick": -12.0,
	"upgrade": -5.0,
	"roll": -8.0, "clack": -9.0, "hold": -10.0, "stamp": -4.0, "steal": -4.0, "bust": -6.0,
	"jackpot": -2.0, "win": -2.0,
	"flip": -9.0, "lock": -3.0,
	"whistle": -12.0, "boom": -3.0, "splash": -7.0, "sunk": -3.0, "sonar": -6.0,
	"scan": -10.0, "unlock": -3.0,
}
const NOTE_DB := -7.0
## Each game has its own soundtrack of three layers: pad, arpeggio, beat.
const ARCADE_MUSIC := ["music_pad", "music_arp", "music_beat"]
const CHESS_MUSIC := ["chess_pad", "chess_arp", "chess_beat"]
const DICE_MUSIC := ["dice_pad", "dice_arp", "dice_beat"]
const FLIP_MUSIC := ["flip_pad", "flip_arp", "flip_beat"]
const FLEET_MUSIC := ["fleet_pad", "fleet_arp", "fleet_beat"]
const GRID_MUSIC := ["grid_pad", "grid_arp", "grid_beat"]
const MUSIC_DB := -9.0
const SILENT_DB := -60.0

var _sfx := {}
var _notes: Array[AudioStream] = []
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: Array[AudioStreamPlayer] = []
var _layer_on: Array[bool] = [true, false, false]
var _duck_tween: Tween
var _music_db := 0.0
var _music_set: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_buses()
	for name: String in TRIM:
		_sfx[name] = load(SFX_DIR + name + ".wav")
	for i in NOTE_COUNT:
		_notes.append(load(SFX_DIR + "note_%02d.wav" % i))
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_pool.append(p)
	for i in ARCADE_MUSIC.size():
		var p := AudioStreamPlayer.new()
		p.bus = &"Music"
		p.volume_db = SILENT_DB
		add_child(p)
		_music.append(p)


## Plays an effect. `pitch_jitter` randomises the pitch a little so repeated
## sounds don't feel robotic.
func play(name: String, pitch: float = 1.0, volume_db: float = 0.0, pitch_jitter: float = 0.0) -> void:
	var stream: AudioStream = _sfx.get(name)
	if stream == null:
		push_warning("No sound named " + name)
		return
	_voice(stream, pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter)), TRIM[name] + volume_db)


## Plays after a delay (in game time, so hit-stop holds it too).
func play_later(delay: float, name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	await get_tree().create_timer(delay, false).timeout
	play(name, pitch, volume_db)


## One step of the pentatonic ladder; higher indexes are higher notes.
## Indexes past the top wrap up an octave via pitch so the ladder keeps rising.
func note(index: int, volume_db: float = 0.0) -> void:
	index = maxi(index, 0)
	var octave := 0
	while index >= NOTE_COUNT:
		index -= 5
		octave += 1
	_voice(_notes[index], pow(2.0, octave), NOTE_DB + volume_db)


func note_later(delay: float, index: int, volume_db: float = 0.0) -> void:
	await get_tree().create_timer(delay, false).timeout
	note(index, volume_db)


## Starts a soundtrack (ARCADE_MUSIC, CHESS_MUSIC or DICE_MUSIC) from the calm layer.
## Does nothing if it's already playing.
func start_music(layers: Array = ARCADE_MUSIC) -> void:
	if layers == _music_set:
		return
	_music_set = layers
	for i in _music.size():
		var stream: AudioStreamWAV = load(MUSIC_DIR + layers[i] + ".wav")
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
		_music[i].stream = stream
		_music[i].volume_db = SILENT_DB
		_music[i].play()
	_layer_on = [true, false, false]
	_apply_layers(0.6)


## Music grows with the run: the pad always plays, the arpeggio joins on a
## streak, and the drums and bass join from a big streak or Fever.
func set_intensity(streak: int, fever: bool) -> void:
	var want: Array[bool] = [true, streak >= 2 or fever, streak >= 4 or fever]
	if want != _layer_on:
		_layer_on = want
		_apply_layers(1.2)


## Player volumes, 0-1 (from Settings). Zero mutes the bus.
func set_volumes(music: float, sfx: float) -> void:
	_music_db = linear_to_db(maxf(music, 0.0001))
	var music_bus := AudioServer.get_bus_index(&"Music")
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	AudioServer.set_bus_volume_db(music_bus, _music_db)
	AudioServer.set_bus_mute(music_bus, music <= 0.001)
	AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(maxf(sfx, 0.0001)))
	AudioServer.set_bus_mute(sfx_bus, sfx <= 0.001)


## Dips the music for a moment so a big effect cuts through.
func duck(amount_db: float = 6.0, hold: float = 0.4) -> void:
	var bus := AudioServer.get_bus_index(&"Music")
	if _duck_tween:
		_duck_tween.kill()
	AudioServer.set_bus_volume_db(bus, _music_db - amount_db)
	_duck_tween = create_tween()
	_duck_tween.tween_interval(hold)
	_duck_tween.tween_method(func(v: float) -> void: AudioServer.set_bus_volume_db(bus, v),
		_music_db - amount_db, _music_db, 0.6)


func _apply_layers(time: float) -> void:
	for i in _music.size():
		var target := MUSIC_DB if _layer_on[i] else SILENT_DB
		create_tween().tween_property(_music[i], "volume_db", target, time) \
			.set_trans(Tween.TRANS_SINE if _layer_on[i] else Tween.TRANS_EXPO)


func _voice(stream: AudioStream, pitch: float, volume_db: float) -> void:
	# Round-robin; if every voice is busy the oldest one gets reused.
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


## SFX and Music buses (for the settings sliders later), with a light reverb
## on effects and a limiter on the master so pile-ups never clip.
func _make_buses() -> void:
	for name: StringName in [&"SFX", &"Music"]:
		if AudioServer.get_bus_index(name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, name)
			AudioServer.set_bus_send(idx, &"Master")
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.45
	reverb.damping = 0.6
	reverb.wet = 0.12
	reverb.dry = 1.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(&"SFX"), reverb)
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, limiter)
