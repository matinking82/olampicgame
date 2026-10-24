class_name Synth
extends RefCounted
## A tiny offline synthesiser. tools/make_audio.gd uses it to render every
## sound in the game into WAV files, so nothing is synthesised at runtime.
## Works on a float buffer; times are in seconds, frequencies in Hz.

enum Wave { SINE, SAW, SQUARE, TRI }
## How a voice's volume moves over its length.
enum Env { DECAY, FADE, SWELL, HOLD }

var rate: int
var buf := PackedFloat32Array()
## Looping buffers wrap anything written past the end back to the start,
## so tails spill over the loop point and the loop is seamless.
var looping := false
var rng := RandomNumberGenerator.new()


func _init(seconds: float, sample_rate: int = 44100, loop: bool = false) -> void:
	rate = sample_rate
	looping = loop
	buf.resize(int(seconds * rate))
	rng.seed = 7


static func midi(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


func add(i: int, v: float) -> void:
	if looping:
		buf[i % buf.size()] += v
	elif i >= 0 and i < buf.size():
		buf[i] += v


## A struck, glassy tone: a sine plus a few quickly fading overtones.
## `bright` scales the overtones (0 is a pure sine).
func bell(start: float, freq: float, dur: float, amp: float, decay: float = 6.0, bright: float = 1.0) -> void:
	var s0 := int(start * rate)
	var w := TAU * freq / rate
	for i in int(dur * rate):
		var t := float(i) / rate
		var v := sin(w * i) * exp(-t * decay)
		v += bright * 0.45 * sin(2.0 * w * i) * exp(-t * decay * 1.8)
		v += bright * 0.18 * sin(3.98 * w * i) * exp(-t * decay * 3.0)
		v += bright * 0.08 * sin(6.3 * w * i) * exp(-t * decay * 5.0)
		add(s0 + i, v * minf(1.0, t / 0.003) * amp)


## An oscillator gliding from f0 to f1 (exponentially), with an envelope.
## `decay` is the exponential rate used by Env.DECAY.
func sweep(start: float, dur: float, f0: float, f1: float, amp: float,
		wave: Wave = Wave.SINE, env: Env = Env.DECAY, decay: float = 8.0, attack: float = 0.003) -> void:
	var s0 := int(start * rate)
	var n := int(dur * rate)
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var k := float(i) / n
		phase += TAU * f0 * pow(f1 / f0, k) / rate
		add(s0 + i, _osc(wave, phase) * _env(env, t, k, decay, attack, dur) * amp)


## Filtered white noise. The low-pass cutoff glides from lp0 to lp1; `hp`
## (if above 0) removes the lows below it.
func noise(start: float, dur: float, amp: float, env: Env = Env.DECAY, decay: float = 10.0,
		lp0: float = 18000.0, lp1: float = 18000.0, hp: float = 0.0, attack: float = 0.001) -> void:
	var s0 := int(start * rate)
	var n := int(dur * rate)
	var low := 0.0
	var high := 0.0
	var b := 1.0 - exp(-TAU * hp / rate)
	for i in n:
		var t := float(i) / rate
		var k := float(i) / n
		var a := 1.0 - exp(-TAU * lp0 * pow(lp1 / lp0, k) / rate)
		low += a * (rng.randf_range(-1.0, 1.0) - low)
		var y := low
		if hp > 0.0:
			high += b * (y - high)
			y -= high
		add(s0 + i, y * _env(env, t, k, decay, attack, dur) * amp)


## A soft synth pad: three slightly detuned saws per note, low-passed,
## fading in over `attack` and out over `release` after `dur`.
func pad(start: float, dur: float, notes: Array, amp: float, cutoff: float = 1400.0,
		attack: float = 0.25, release: float = 0.5) -> void:
	var s0 := int(start * rate)
	var total := int((dur + release) * rate)
	var a := 1.0 - exp(-TAU * cutoff / rate)
	var phases := PackedFloat32Array()
	var steps := PackedFloat32Array()
	for note: float in notes:
		for detune: float in [0.997, 1.0, 1.003]:
			phases.append(rng.randf())
			steps.append(midi(note) * detune / rate)
	var lp1 := 0.0
	var lp2 := 0.0
	for i in total:
		var t := float(i) / rate
		var x := 0.0
		for v in phases.size():
			phases[v] = fmod(phases[v] + steps[v], 1.0)
			x += phases[v] * 2.0 - 1.0
		lp1 += a * (x - lp1)
		lp2 += a * (lp1 - lp2)
		var env := minf(1.0, t / attack)
		if t > dur:
			env *= 1.0 - (t - dur) / release
		add(s0 + i, lp2 * env * amp / phases.size())


func kick(start: float, amp: float) -> void:
	sweep(start, 0.32, 150.0, 42.0, amp, Wave.SINE, Env.DECAY, 9.0, 0.001)
	noise(start, 0.01, amp * 0.3, Env.DECAY, 300.0, 4000.0, 4000.0)


func clap(start: float, amp: float) -> void:
	for k in 3:
		noise(start + k * 0.011, 0.02, amp * 0.5, Env.DECAY, 120.0, 5000.0, 5000.0, 900.0)
	noise(start + 0.03, 0.18, amp, Env.DECAY, 22.0, 6000.0, 3000.0, 900.0)


func hat(start: float, amp: float, length: float = 0.05) -> void:
	noise(start, length, amp, Env.DECAY, 70.0, 18000.0, 18000.0, 7000.0)


## Low-pass filters the whole buffer (two one-pole passes).
func lowpass(cutoff: float) -> void:
	var a := 1.0 - exp(-TAU * cutoff / rate)
	for _pass in 2:
		var y := 0.0
		for i in buf.size():
			y += a * (buf[i] - y)
			buf[i] = y


## Adds another buffer into this one at `start`, scaled by `gain`.
func mix(other: Synth, start: float = 0.0, gain: float = 1.0) -> void:
	var s0 := int(start * rate)
	for i in other.buf.size():
		add(s0 + i, other.buf[i] * gain)


func normalize(peak: float = 0.9) -> void:
	var top := 0.0
	for v in buf:
		top = maxf(top, absf(v))
	if top > 0.0:
		for i in buf.size():
			buf[i] *= peak / top


## Short fades at both ends so one-shots never click.
func smooth_edges(seconds: float = 0.004) -> void:
	var n := mini(int(seconds * rate), buf.size() / 2)
	for i in n:
		var g := float(i) / n
		buf[i] *= g
		buf[buf.size() - 1 - i] *= g


func save(path: String) -> void:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	wav.save_to_wav(path)


func _osc(wave: Wave, phase: float) -> float:
	match wave:
		Wave.SAW:
			return fposmod(phase / TAU, 1.0) * 2.0 - 1.0
		Wave.SQUARE:
			return 1.0 if sin(phase) >= 0.0 else -1.0
		Wave.TRI:
			return absf(fposmod(phase / TAU, 1.0) * 4.0 - 2.0) - 1.0
	return sin(phase)


func _env(env: Env, t: float, k: float, decay: float, attack: float, dur: float) -> float:
	var a := minf(1.0, t / attack)
	match env:
		Env.FADE:
			return a * (1.0 - k)
		Env.SWELL:
			return k * k * minf(1.0, (dur - t) / 0.01)
		Env.HOLD:
			return a * minf(1.0, (dur - t) / 0.01)
	return a * exp(-t * decay)
