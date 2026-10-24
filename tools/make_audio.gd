extends SceneTree
## Renders every sound in the game into audio/sfx and audio/music.
## Run from the "My project" folder, then re-import:
##   Godot_v4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path sudoku-pop --script res://tools/make_audio.gd
##   Godot_v4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path sudoku-pop --import
## Add "-- --only=flip,code" to render just some games' sounds
## (sudoku, chess, dice, flip, fleet, grid).

const SFX_DIR := "res://audio/sfx/"
const MUSIC_DIR := "res://audio/music/"
## C major pentatonic from C5 up: the notes pops climb through.
const PENTATONIC := [72, 74, 76, 79, 81, 84, 86, 88, 91, 93, 96, 98, 100]

const BPM := 100.0
const BEAT := 60.0 / BPM
const BAR := BEAT * 4.0
const MUSIC_RATE := 32000
## Eight bars: C G Am F | C G F G. Each chord: pad voicing, bass note, arp notes.
const CHORDS := [
	[[60, 64, 67, 48], 36, [72, 76, 79, 84, 88, 84, 79, 76]],
	[[59, 62, 67, 43], 43, [71, 74, 79, 83, 86, 83, 79, 74]],
	[[60, 64, 69, 45], 45, [69, 72, 76, 81, 84, 81, 76, 72]],
	[[60, 65, 69, 41], 41, [69, 72, 77, 81, 84, 81, 77, 72]],
	[[60, 64, 67, 48], 36, [72, 79, 84, 88, 91, 88, 84, 79]],
	[[59, 62, 67, 43], 43, [74, 79, 83, 86, 91, 86, 83, 79]],
	[[60, 65, 69, 41], 41, [72, 77, 81, 84, 89, 84, 81, 77]],
	[[59, 62, 67, 43], 43, [74, 79, 83, 86, 83, 79, 74, 71]],
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SFX_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MUSIC_DIR))
	var only := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = Array(a.trim_prefix("--only=").split(","))
	var start := Time.get_ticks_msec()
	var games := {
		"sudoku": [_make_sfx, _make_music], "chess": [_make_chess_sfx, _make_chess_music],
		"dice": [_make_dice_sfx, _make_dice_music], "flip": [_make_flip_sfx, _make_flip_music],
		"fleet": [_make_fleet_sfx, _make_fleet_music],
		"grid": [_make_grid_sfx, _make_grid_music],
	}
	for game: String in games:
		if only.is_empty() or only.has(game):
			for make: Callable in games[game]:
				make.call()
	print("audio rendered in %.1f s" % ((Time.get_ticks_msec() - start) / 1000.0))
	quit()


# --- Sound effects -------------------------------------------------------------

func _make_sfx() -> void:
	# The pop notes: a glassy bell with a little water-drop "bloop" up front.
	for i in PENTATONIC.size():
		var f := Synth.midi(PENTATONIC[i])
		var s := Synth.new(0.9)
		s.sweep(0, 0.05, f * 0.5, f, 0.5, Synth.Wave.SINE, Synth.Env.DECAY, 40.0, 0.001)
		s.bell(0, f, 0.9, 1.0, 5.5)
		_save(s, "note_%02d" % i, 0.75)

	var s: Synth

	s = Synth.new(0.1)
	s.sweep(0, 0.09, 420, 900, 1.0, Synth.Wave.SINE, Synth.Env.FADE)
	s.sweep(0, 0.06, 840, 1800, 0.3, Synth.Wave.SINE, Synth.Env.FADE)
	_save(s, "pickup")

	# Candy "thock": a dropping thump, a click and a tiny glassy ting.
	s = Synth.new(0.16)
	s.sweep(0, 0.14, 260, 90, 1.0, Synth.Wave.SINE, Synth.Env.DECAY, 28.0, 0.001)
	s.noise(0, 0.015, 0.5, Synth.Env.DECAY, 300.0, 9000.0, 9000.0, 1500.0)
	s.bell(0, 1760, 0.12, 0.15, 40.0, 0.3)
	_save(s, "place")

	s = Synth.new(0.07)
	s.sweep(0, 0.06, 700, 1300, 0.6, Synth.Wave.TRI, Synth.Env.FADE)
	s.noise(0, 0.05, 0.25, Synth.Env.DECAY, 50.0, 3000.0, 9000.0, 1000.0)
	_save(s, "rotate", 0.6)

	s = Synth.new(0.26)
	s.sweep(0, 0.09, 330, 300, 0.6, Synth.Wave.TRI, Synth.Env.HOLD)
	s.sweep(0.11, 0.14, 235, 200, 0.6, Synth.Wave.TRI, Synth.Env.FADE)
	_save(s, "invalid", 0.6)

	# Groups getting sucked into their merge cell.
	s = Synth.new(0.18)
	s.noise(0, 0.17, 1.0, Synth.Env.SWELL, 0.0, 400.0, 7000.0)
	s.sweep(0, 0.17, 300, 1300, 0.35, Synth.Wave.SINE, Synth.Env.SWELL)
	_save(s, "suck", 0.6)

	# Sudoku blast: a bright major chord stab, a whoosh, a punchy kick and sparkles.
	var chord := Synth.new(1.4)
	for m in [72, 76, 79, 84]:
		for detune in [0.996, 1.004]:
			chord.sweep(0, 1.35, Synth.midi(m) * detune, Synth.midi(m) * detune, 0.25, Synth.Wave.SAW, Synth.Env.DECAY, 3.0, 0.004)
	chord.lowpass(3200)
	s = Synth.new(1.4)
	s.mix(chord)
	s.noise(0, 0.8, 0.7, Synth.Env.DECAY, 5.0, 9000.0, 500.0)
	s.kick(0, 1.0)
	for k in 6:
		s.bell(0.06 + k * 0.07, Synth.midi(PENTATONIC[6 + k]), 0.5, 0.18, 8.0)
	_save(s, "blast")

	# Golden star: a fast bell glissando and a deep boom.
	s = Synth.new(1.2)
	for k in 10:
		s.bell(k * 0.035, Synth.midi(PENTATONIC[k + 2]), 0.6, 0.35, 7.0)
	s.noise(0, 1.0, 0.8, Synth.Env.DECAY, 4.0, 1500.0, 200.0)
	s.kick(0, 1.0)
	_save(s, "star")

	# Power earned: the classic two-note coin.
	s = Synth.new(0.55)
	s.bell(0, 988, 0.1, 0.6, 25.0, 0.6)
	s.bell(0.07, 1319, 0.45, 0.7, 8.0, 0.6)
	_save(s, "coin", 0.7)

	s = Synth.new(1.3)
	var arp := [72, 76, 79, 84, 88, 91, 96]
	for k in arp.size():
		s.bell(k * 0.065, Synth.midi(arp[k]), 1.2 - k * 0.065, 0.5, 4.5 if k == arp.size() - 1 else 7.0)
	_save(s, "level_up", 0.8)

	s = Synth.new(2.0)
	s.mix(chord, 0.0, 0.8)
	for k in arp.size():
		s.bell(0.1 + k * 0.06, Synth.midi(arp[k]), 1.4, 0.45, 4.0)
	s.noise(0.3, 1.6, 0.25, Synth.Env.DECAY, 2.0, 12000.0, 12000.0, 6000.0)
	_save(s, "perfect")

	# Fever: a rising, opening riser that ends on a sparkle.
	var riser := Synth.new(1.2)
	riser.sweep(0, 1.1, 150, 900, 0.5, Synth.Wave.SAW, Synth.Env.SWELL)
	riser.sweep(0, 1.1, 151, 905, 0.5, Synth.Wave.SAW, Synth.Env.SWELL)
	riser.lowpass(2500)
	s = Synth.new(1.6)
	s.mix(riser)
	s.noise(0, 1.1, 0.5, Synth.Env.SWELL, 0.0, 500.0, 9000.0)
	s.bell(1.1, 2093, 0.5, 0.5, 6.0)
	s.bell(1.15, 2637, 0.45, 0.4, 6.0)
	_save(s, "fever")

	s = Synth.new(0.4)
	s.sweep(0, 0.38, 120, 40, 1.0, Synth.Wave.SINE, Synth.Env.DECAY, 10.0, 0.002)
	s.noise(0, 0.15, 0.5, Synth.Env.DECAY, 25.0, 800.0, 800.0)
	_save(s, "thud")

	s = Synth.new(0.16)
	s.noise(0, 0.12, 0.8, Synth.Env.DECAY, 30.0, 9000.0, 9000.0, 1200.0)
	for k in 6:
		s.noise(randf() * 0.1, 0.006, 0.9, Synth.Env.DECAY, 400.0, 12000.0, 12000.0, 2000.0)
	_save(s, "crack", 0.7)

	var zap := Synth.new(0.5)
	zap.sweep(0, 0.45, 1800, 120, 0.6, Synth.Wave.SAW, Synth.Env.DECAY, 4.0)
	zap.sweep(0, 0.45, 1812, 124, 0.6, Synth.Wave.SAW, Synth.Env.DECAY, 4.0)
	zap.lowpass(5000)
	s = Synth.new(0.5)
	s.mix(zap)
	s.noise(0, 0.3, 0.3, Synth.Env.DECAY, 10.0, 8000.0, 2000.0, 1500.0)
	_save(s, "laser")

	s = Synth.new(1.1)
	s.noise(0, 1.05, 1.0, Synth.Env.DECAY, 4.0, 3000.0, 150.0)
	s.sweep(0, 0.6, 110, 35, 1.0, Synth.Wave.SINE, Synth.Env.DECAY, 5.0, 0.002)
	_save(s, "bomb")

	s = Synth.new(1.3)
	s.noise(0, 1.0, 0.7, Synth.Env.DECAY, 3.0, 2000.0, 120.0)
	s.sweep(0, 0.9, 90, 30, 1.0, Synth.Wave.SINE, Synth.Env.DECAY, 3.0, 0.002)
	for k in 8:
		s.bell(0.25 + k * 0.05, Synth.midi(PENTATONIC[12 - k]), 0.5, 0.25, 7.0)
	_save(s, "nuke")

	s = Synth.new(0.55)
	s.bell(0, 523, 0.5, 0.6, 12.0, 0.2)
	s.bell(0, 1347, 0.4, 0.4, 16.0, 0.2)
	s.bell(0, 2113, 0.3, 0.3, 20.0, 0.2)
	s.sweep(0, 0.2, 140, 50, 0.6, Synth.Wave.SINE, Synth.Env.DECAY, 15.0, 0.001)
	_save(s, "hammer")

	s = Synth.new(2.2)
	s.pad(0, 1.4, [48, 52, 55], 0.6, 900.0, 0.3, 0.7)
	for k in 3:
		s.bell(k * 0.3, Synth.midi([67, 64, 60][k]), 1.5, 0.6, 3.0)
	_save(s, "game_over", 0.8)

	s = Synth.new(0.035)
	s.sweep(0, 0.03, 1500, 1200, 0.5, Synth.Wave.SINE, Synth.Env.DECAY, 120.0, 0.001)
	_save(s, "click", 0.5)

	s = Synth.new(0.07)
	s.noise(0, 0.06, 0.8, Synth.Env.DECAY, 60.0, 6000.0, 6000.0, 1500.0)
	s.sweep(0, 0.05, 900, 1400, 0.25, Synth.Wave.TRI, Synth.Env.DECAY, 60.0)
	_save(s, "deal", 0.5)

	s = Synth.new(0.55)
	for k in 2:
		s.sweep(k * 0.26, 0.12, 880, 880, 0.5, Synth.Wave.TRI, Synth.Env.HOLD)
		s.sweep(k * 0.26 + 0.13, 0.12, 660, 660, 0.5, Synth.Wave.TRI, Synth.Env.HOLD)
	_save(s, "alarm", 0.6)

	s = Synth.new(0.3)
	s.noise(0, 0.28, 1.0, Synth.Env.SWELL, 0.0, 600.0, 5000.0)
	_save(s, "whoosh", 0.5)


# --- Merge Mate's effects -----------------------------------------------------------

func _make_chess_sfx() -> void:
	var s: Synth

	# A piece set down: a hollow candy "tock" with a woody knock.
	s = Synth.new(0.2)
	s.sweep(0, 0.16, 210, 120, 1.0, Synth.Wave.SINE, Synth.Env.DECAY, 30.0, 0.001)
	s.bell(0, 640, 0.12, 0.35, 45.0, 0.2)
	s.noise(0, 0.012, 0.45, Synth.Env.DECAY, 400.0, 7000.0, 7000.0, 1800.0)
	_save(s, "move", 0.75)

	# A capture: a crunchy pop, a thump and a shower of sparkles.
	s = Synth.new(0.7)
	s.noise(0, 0.25, 1.0, Synth.Env.DECAY, 18.0, 11000.0, 1500.0, 900.0)
	s.sweep(0, 0.3, 300, 60, 1.0, Synth.Wave.SINE, Synth.Env.DECAY, 12.0, 0.001)
	s.sweep(0, 0.08, 1200, 400, 0.35, Synth.Wave.SQUARE, Synth.Env.DECAY, 40.0, 0.001)
	for k in 5:
		s.bell(0.04 + k * 0.045, Synth.midi(PENTATONIC[12 - k * 2]), 0.35, 0.22, 10.0)
	_save(s, "capture")

	# Check: a bright two-note alert that climbs.
	s = Synth.new(0.7)
	for k in 2:
		var f := Synth.midi([84, 91][k])
		s.sweep(k * 0.12, 0.1, f * 0.98, f, 0.4, Synth.Wave.SQUARE, Synth.Env.HOLD)
		s.bell(k * 0.12, f, 0.5, 0.6, 7.0)
	s.lowpass(6000)
	_save(s, "check", 0.75)

	# Checkmate: a brassy major fanfare, a boom and falling sparkles.
	var brass := Synth.new(2.4)
	var fanfare := [[0.0, [69, 73, 76]], [0.16, [69, 73, 76]], [0.32, [71, 74, 78]], [0.5, [73, 76, 81, 85]]]
	for hit: Array in fanfare:
		var dur := 1.8 if hit[0] >= 0.5 else 0.15
		for m: int in hit[1]:
			for detune in [0.995, 1.005]:
				brass.sweep(hit[0], dur, Synth.midi(m) * detune, Synth.midi(m) * detune, 0.22,
					Synth.Wave.SAW, Synth.Env.DECAY, 2.0 if dur > 1.0 else 12.0, 0.01)
	brass.lowpass(3600)
	s = Synth.new(2.6)
	s.mix(brass)
	s.kick(0.5, 1.0)
	s.noise(0.5, 1.5, 0.5, Synth.Env.DECAY, 3.0, 9000.0, 600.0)
	for k in 10:
		s.bell(0.6 + k * 0.08, Synth.midi(PENTATONIC[12 - k]), 0.8, 0.3, 6.0)
	_save(s, "mate")

	# A new piece dropping onto its home row.
	s = Synth.new(0.22)
	s.sweep(0, 0.05, 900, 1500, 0.3, Synth.Wave.SINE, Synth.Env.FADE)
	s.sweep(0.03, 0.17, 180, 90, 0.9, Synth.Wave.SINE, Synth.Env.DECAY, 25.0, 0.001)
	s.bell(0.03, 1320, 0.15, 0.2, 30.0, 0.4)
	_save(s, "drop", 0.6)

	# The slot-machine tick while a pawn merge picks knight or bishop.
	s = Synth.new(0.04)
	s.sweep(0, 0.035, 2400, 1800, 0.6, Synth.Wave.TRI, Synth.Env.DECAY, 90.0, 0.0005)
	s.noise(0, 0.01, 0.3, Synth.Env.DECAY, 400.0, 9000.0, 9000.0, 3000.0)
	_save(s, "tick", 0.5)

	# The Upgrade power: a rising shimmer that lands on a bell chord.
	var shimmer := Synth.new(0.9)
	shimmer.sweep(0, 0.5, 300, 1500, 0.4, Synth.Wave.SAW, Synth.Env.SWELL)
	shimmer.sweep(0, 0.5, 303, 1512, 0.4, Synth.Wave.SAW, Synth.Env.SWELL)
	shimmer.lowpass(4000)
	s = Synth.new(1.2)
	s.mix(shimmer)
	s.noise(0, 0.5, 0.3, Synth.Env.SWELL, 0.0, 800.0, 10000.0)
	for m in [76, 81, 88]:
		s.bell(0.5, Synth.midi(m), 0.7, 0.4, 5.0)
	_save(s, "upgrade", 0.8)


# --- Tic Tac Roll's effects ------------------------------------------------------------

func _make_dice_sfx() -> void:
	var s: Synth

	# Dice rattling in a cup and spilling out: a flurry of little knocks.
	s = Synth.new(0.42)
	for k in 14:
		var t := 0.02 * k + randf() * 0.012
		s.noise(t, 0.02, 0.5 + 0.3 * randf(), Synth.Env.DECAY, 220.0, 8000.0, 8000.0, 1500.0)
		s.bell(t, randf_range(1400.0, 2600.0), 0.03, 0.12, 120.0, 0.2)
	s.noise(0, 0.4, 0.25, Synth.Env.SWELL, 0.0, 900.0, 4000.0, 300.0)
	_save(s, "roll", 0.7)

	# One die landing: a hard candy knock.
	s = Synth.new(0.12)
	s.bell(0, 1900, 0.08, 0.5, 70.0, 0.4)
	s.bell(0, 3100, 0.05, 0.25, 90.0, 0.3)
	s.sweep(0, 0.08, 420, 180, 0.6, Synth.Wave.SINE, Synth.Env.DECAY, 45.0, 0.0005)
	s.noise(0, 0.015, 0.6, Synth.Env.DECAY, 300.0, 10000.0, 10000.0, 2500.0)
	_save(s, "clack", 0.6)

	# Holding a die: a soft rising bloop.
	s = Synth.new(0.12)
	s.sweep(0, 0.11, 520, 980, 0.8, Synth.Wave.SINE, Synth.Env.FADE)
	s.bell(0.02, 1960, 0.08, 0.2, 30.0, 0.4)
	_save(s, "hold", 0.6)

	# Claiming a cell: a punchy stamp with a bright little chord on top.
	s = Synth.new(0.5)
	s.sweep(0, 0.22, 240, 70, 1.0, Synth.Wave.SINE, Synth.Env.DECAY, 18.0, 0.001)
	s.noise(0, 0.03, 0.6, Synth.Env.DECAY, 150.0, 6000.0, 6000.0, 800.0)
	for m in [77, 81, 84]:
		s.bell(0.01, Synth.midi(m), 0.4, 0.3, 9.0)
	_save(s, "stamp", 0.8)

	# A steal: a greedy zip down then up, and a snatch.
	var zip := Synth.new(0.45)
	zip.sweep(0, 0.18, 1600, 300, 0.45, Synth.Wave.SAW, Synth.Env.HOLD)
	zip.sweep(0.18, 0.2, 300, 2200, 0.45, Synth.Wave.SAW, Synth.Env.FADE)
	zip.lowpass(4500)
	s = Synth.new(0.6)
	s.mix(zip)
	s.noise(0, 0.38, 0.4, Synth.Env.SWELL, 0.0, 600.0, 9000.0)
	s.bell(0.38, 1760, 0.2, 0.5, 14.0)
	s.bell(0.43, 2349, 0.15, 0.4, 14.0)
	_save(s, "steal")

	# Nothing fits: a sad trombone "wah wah".
	s = Synth.new(0.9)
	for k in 2:
		var f := Synth.midi([58, 55][k])
		s.sweep(k * 0.3, 0.32 if k == 0 else 0.55, f, f * (0.97 if k == 0 else 0.9), 0.5, Synth.Wave.SAW, Synth.Env.HOLD)
	s.lowpass(1400)
	_save(s, "bust", 0.6)

	# Five of a kind: a slot-machine payout of bells over a bright chord.
	var stab := Synth.new(1.8)
	for m in [65, 69, 72, 77]:
		for detune in [0.996, 1.004]:
			stab.sweep(0, 1.7, Synth.midi(m) * detune, Synth.midi(m) * detune, 0.22, Synth.Wave.SAW, Synth.Env.DECAY, 2.5, 0.004)
	stab.lowpass(3600)
	s = Synth.new(2.0)
	s.mix(stab)
	s.kick(0, 1.0)
	for k in 18:
		s.bell(0.05 + k * 0.05, Synth.midi(PENTATONIC[k % 13] + (0 if k < 13 else 12)), 0.4, 0.3, 9.0)
	s.noise(0, 1.2, 0.35, Synth.Env.DECAY, 2.5, 12000.0, 3000.0, 4000.0)
	_save(s, "jackpot")

	# Four in a row: a brassy fanfare in F, a boom and falling sparkles.
	var brass := Synth.new(2.4)
	var fanfare := [[0.0, [65, 69, 72]], [0.14, [65, 69, 72]], [0.28, [67, 70, 74]], [0.46, [69, 72, 77, 81]]]
	for hit: Array in fanfare:
		var dur := 1.8 if hit[0] >= 0.46 else 0.13
		for m: int in hit[1]:
			for detune in [0.995, 1.005]:
				brass.sweep(hit[0], dur, Synth.midi(m) * detune, Synth.midi(m) * detune, 0.22,
					Synth.Wave.SAW, Synth.Env.DECAY, 2.0 if dur > 1.0 else 12.0, 0.01)
	brass.lowpass(3800)
	s = Synth.new(2.6)
	s.mix(brass)
	s.kick(0.46, 1.0)
	s.noise(0.46, 1.5, 0.5, Synth.Env.DECAY, 3.0, 9000.0, 600.0)
	for k in 10:
		s.bell(0.56 + k * 0.07, Synth.midi(PENTATONIC[12 - k]), 0.8, 0.3, 6.0)
	_save(s, "win")


func _make_flip_sfx() -> void:
	var s: Synth

	# A disc turning over: a light plastic tick with a quick upward blip.
	s = Synth.new(0.1)
	s.noise(0, 0.012, 0.5, Synth.Env.DECAY, 400.0, 9000.0, 9000.0, 3000.0)
	s.sweep(0.005, 0.06, 900, 1700, 0.5, Synth.Wave.SINE, Synth.Env.DECAY, 40.0, 0.001)
	s.bell(0.01, 2600, 0.05, 0.12, 60.0, 0.3)
	_save(s, "flip", 0.6)

	# Locking a line: a low thump, a rising bell chord and a sparkly shimmer.
	s = Synth.new(1.2)
	s.sweep(0, 0.25, 160, 60, 0.9, Synth.Wave.SINE, Synth.Env.DECAY, 14.0, 0.001)
	for k in 4:
		s.bell(0.04 + 0.06 * k, Synth.midi([72, 76, 79, 84][k]), 0.9, 0.35, 5.0)
	s.noise(0.05, 0.9, 0.22, Synth.Env.DECAY, 4.0, 14000.0, 6000.0, 5000.0)
	_save(s, "lock")


func _make_fleet_sfx() -> void:
	var s: Synth

	# A bomb falling: a wobbling whistle sliding down.
	s = Synth.new(0.36)
	s.sweep(0, 0.34, 2100, 700, 0.5, Synth.Wave.SINE, Synth.Env.HOLD)
	s.sweep(0, 0.34, 2130, 712, 0.25, Synth.Wave.SINE, Synth.Env.HOLD)
	s.noise(0, 0.34, 0.08, Synth.Env.SWELL, 0.0, 3000.0, 6000.0, 1500.0)
	_save(s, "whistle", 0.5)

	# A hit: a deep boom, a crack and crackling embers.
	s = Synth.new(1.0)
	s.sweep(0, 0.5, 140, 38, 1.0, Synth.Wave.SINE, Synth.Env.DECAY, 6.0, 0.001)
	s.noise(0, 0.6, 0.9, Synth.Env.DECAY, 7.0, 2500.0, 300.0)
	s.noise(0, 0.03, 0.7, Synth.Env.DECAY, 100.0, 9000.0, 9000.0, 2000.0)
	for k in 10:
		s.noise(0.15 + randf() * 0.6, 0.012, 0.25, Synth.Env.DECAY, 300.0, 7000.0, 7000.0, 2500.0)
	_save(s, "boom")

	# A miss: a splash of water and a few bubbles.
	s = Synth.new(0.7)
	s.noise(0, 0.5, 0.7, Synth.Env.DECAY, 7.0, 6000.0, 1500.0, 900.0)
	for k in 5:
		var t := 0.12 + 0.07 * k + randf() * 0.03
		var f := randf_range(500.0, 900.0)
		s.sweep(t, 0.06, f, f * 1.8, 0.25, Synth.Wave.SINE, Synth.Env.DECAY, 30.0, 0.002)
	_save(s, "splash", 0.7)

	# A ship sunk: a big gong, falling bells and a rumble.
	s = Synth.new(2.0)
	s.bell(0, 110, 1.9, 0.6, 1.6, 0.6)
	s.bell(0, 164.8, 1.6, 0.35, 2.0, 0.5)
	s.sweep(0, 0.6, 90, 40, 0.8, Synth.Wave.SINE, Synth.Env.DECAY, 5.0, 0.002)
	for k in 8:
		s.bell(0.1 + k * 0.08, Synth.midi(PENTATONIC[12 - k]), 0.7, 0.3, 6.0)
	s.noise(0, 1.4, 0.3, Synth.Env.DECAY, 2.5, 1200.0, 200.0)
	_save(s, "sunk")

	# SONAR: a ping and its echo.
	s = Synth.new(1.2)
	for k in 3:
		s.bell(k * 0.28, 1320, 0.8, 0.5 * pow(0.45, k), 4.0, 0.15)
		s.bell(k * 0.28, 1980, 0.5, 0.15 * pow(0.45, k), 6.0, 0.1)
	_save(s, "sonar", 0.7)


func _make_grid_sfx() -> void:
	var s: Synth

	# A check scanning the grid: a soft rising chirp with little blips.
	s = Synth.new(0.6)
	s.sweep(0, 0.55, 400, 1600, 0.35, Synth.Wave.TRI, Synth.Env.FADE)
	for k in 6:
		s.bell(0.05 + 0.08 * k, 1800 + 200 * k, 0.05, 0.15, 50.0, 0.2)
	_save(s, "scan", 0.6)

	# A code cracked: two lock clicks, a rising sparkle and a warm chord.
	s = Synth.new(1.8)
	for k in 2:
		s.noise(0.08 * k, 0.015, 0.6, Synth.Env.DECAY, 250.0, 7000.0, 7000.0, 2500.0)
		s.bell(0.08 * k, 2400, 0.04, 0.3, 80.0, 0.3)
	for k in 8:
		s.bell(0.2 + 0.05 * k, Synth.midi(PENTATONIC[k + 3]), 0.6, 0.25, 6.0)
	for m in [69, 73, 76, 81]:
		s.bell(0.6, Synth.midi(m), 1.1, 0.3, 2.5, 0.4)
	s.noise(0.6, 1.0, 0.2, Synth.Env.DECAY, 3.0, 12000.0, 5000.0, 5000.0)
	_save(s, "unlock")


# --- Music -----------------------------------------------------------------------
# Three loops of the same length that play together and fade in with the
# streak: a calm pad, a plucked arpeggio, then drums and bass.

func _make_music() -> void:
	var length := BAR * CHORDS.size()

	var pad := Synth.new(length, MUSIC_RATE, true)
	for b in CHORDS.size():
		pad.pad(b * BAR, BAR, CHORDS[b][0], 1.0, 1300.0, 0.35, 0.6)
	_save(pad, "music_pad", 0.5, MUSIC_DIR)

	var arp := Synth.new(length, MUSIC_RATE, true)
	for b in CHORDS.size():
		var notes: Array = CHORDS[b][2]
		for k in notes.size():
			arp.bell(b * BAR + k * BEAT * 0.5, Synth.midi(notes[k]), 0.6, 0.5 if k % 2 == 0 else 0.35, 7.0, 0.5)
	_save(arp, "music_arp", 0.45, MUSIC_DIR)

	var beat := Synth.new(length, MUSIC_RATE, true)
	for b in CHORDS.size():
		var t0 := b * BAR
		var root := Synth.midi(CHORDS[b][1])
		for q in 8:
			var t := t0 + q * BEAT * 0.5
			beat.hat(t, 0.25 if q % 2 == 0 else 0.15)
			beat.sweep(t, BEAT * 0.45, root, root, 0.45, Synth.Wave.TRI, Synth.Env.DECAY, 6.0, 0.004)
			beat.sweep(t, BEAT * 0.45, root * 2.0, root * 2.0, 0.12, Synth.Wave.SINE, Synth.Env.DECAY, 8.0, 0.004)
		beat.kick(t0, 1.0)
		beat.kick(t0 + BEAT * 2.0, 1.0)
		beat.kick(t0 + BEAT * 2.5, 0.6)
		beat.clap(t0 + BEAT, 0.5)
		beat.clap(t0 + BEAT * 3.0, 0.5)
	_save(beat, "music_beat", 0.55, MUSIC_DIR)


## Merge Mate's soundtrack: the same three-layer idea in A minor at a
## brisker 112 bpm, with a plucked arpeggio and a four-on-the-floor beat.
## Am F C G | Am F G E.
const CHESS_BPM := 112.0
const CHESS_CHORDS := [
	[[57, 60, 64, 45], 45, [69, 72, 76, 81, 76, 72, 69, 76]],
	[[57, 60, 65, 41], 41, [65, 69, 72, 77, 72, 69, 65, 72]],
	[[55, 60, 64, 48], 36, [67, 72, 76, 79, 76, 72, 67, 76]],
	[[55, 59, 62, 43], 43, [67, 71, 74, 79, 74, 71, 67, 74]],
	[[57, 60, 64, 45], 45, [69, 72, 76, 81, 84, 81, 76, 72]],
	[[57, 60, 65, 41], 41, [69, 72, 77, 81, 84, 81, 77, 72]],
	[[55, 59, 62, 43], 43, [71, 74, 79, 83, 86, 83, 79, 74]],
	[[56, 59, 64, 40], 40, [68, 71, 76, 80, 83, 80, 76, 71]],
]


func _make_chess_music() -> void:
	var beat_len := 60.0 / CHESS_BPM
	var bar := beat_len * 4.0
	var length := bar * CHESS_CHORDS.size()

	var pad := Synth.new(length, MUSIC_RATE, true)
	for b in CHESS_CHORDS.size():
		pad.pad(b * bar, bar, CHESS_CHORDS[b][0], 1.0, 1100.0, 0.3, 0.55)
	_save(pad, "chess_pad", 0.5, MUSIC_DIR)

	var arp := Synth.new(length, MUSIC_RATE, true)
	for b in CHESS_CHORDS.size():
		var notes: Array = CHESS_CHORDS[b][2]
		for k in notes.size():
			var t: float = b * bar + k * beat_len * 0.5
			var f := Synth.midi(notes[k])
			arp.sweep(t, beat_len * 0.6, f, f, 0.5 if k % 2 == 0 else 0.35, Synth.Wave.TRI, Synth.Env.DECAY, 9.0, 0.002)
			arp.bell(t, f * 2.0, 0.3, 0.12, 12.0, 0.3)
	arp.lowpass(5000)
	_save(arp, "chess_arp", 0.45, MUSIC_DIR)

	var beat := Synth.new(length, MUSIC_RATE, true)
	for b in CHESS_CHORDS.size():
		var t0: float = b * bar
		var root := Synth.midi(CHESS_CHORDS[b][1])
		for q in 16:
			beat.hat(t0 + q * beat_len * 0.25, [0.22, 0.08, 0.14, 0.08][q % 4], 0.035)
		for q in 8:
			var t := t0 + q * beat_len * 0.5
			var f := root * (2.0 if q % 2 == 1 else 1.0)
			beat.sweep(t, beat_len * 0.4, f, f, 0.42, Synth.Wave.TRI, Synth.Env.DECAY, 7.0, 0.004)
		for q in 4:
			beat.kick(t0 + q * beat_len, 0.9)
		beat.clap(t0 + beat_len, 0.5)
		beat.clap(t0 + beat_len * 3.0, 0.5)
	_save(beat, "chess_beat", 0.55, MUSIC_DIR)


## Tic Tac Roll's soundtrack: a bouncy, swung groove in F major at 118 bpm
## with a marimba arpeggio and a shaker beat. F Dm Bb C | F Am Bb C.
const DICE_BPM := 118.0
const DICE_CHORDS := [
	[[57, 60, 65, 41], 41, [65, 69, 72, 77, 72, 69, 65, 69]],
	[[57, 62, 65, 38], 38, [62, 65, 69, 74, 69, 65, 62, 65]],
	[[58, 62, 65, 46], 34, [62, 65, 70, 74, 70, 65, 62, 65]],
	[[55, 60, 64, 48], 36, [64, 67, 72, 76, 72, 67, 64, 67]],
	[[57, 60, 65, 41], 41, [69, 72, 77, 81, 77, 72, 69, 72]],
	[[57, 60, 64, 45], 45, [69, 72, 76, 81, 76, 72, 69, 72]],
	[[58, 62, 65, 46], 34, [70, 74, 77, 82, 77, 74, 70, 74]],
	[[55, 60, 64, 48], 36, [72, 76, 79, 84, 79, 76, 72, 67]],
]
## Off-beat eighths land this far through the beat (0.5 is straight).
const DICE_SWING := 0.6


func _make_dice_music() -> void:
	var beat_len := 60.0 / DICE_BPM
	var bar := beat_len * 4.0
	var length := bar * DICE_CHORDS.size()
	var eighth := func(q: int) -> float: return (q / 2 + (DICE_SWING if q % 2 == 1 else 0.0)) * beat_len

	var pad := Synth.new(length, MUSIC_RATE, true)
	for b in DICE_CHORDS.size():
		pad.pad(b * bar, bar, DICE_CHORDS[b][0], 1.0, 1500.0, 0.3, 0.6)
	_save(pad, "dice_pad", 0.5, MUSIC_DIR)

	# Marimba: a soft sine knock with a woody overtone.
	var arp := Synth.new(length, MUSIC_RATE, true)
	for b in DICE_CHORDS.size():
		var notes: Array = DICE_CHORDS[b][2]
		for k in notes.size():
			var t: float = b * bar + eighth.call(k)
			var f := Synth.midi(notes[k])
			var amp := 0.5 if k % 2 == 0 else 0.36
			arp.sweep(t, beat_len * 0.5, f, f, amp, Synth.Wave.SINE, Synth.Env.DECAY, 11.0, 0.002)
			arp.bell(t, f * 4.0, 0.12, amp * 0.25, 40.0, 0.2)
	_save(arp, "dice_arp", 0.45, MUSIC_DIR)

	var beat := Synth.new(length, MUSIC_RATE, true)
	for b in DICE_CHORDS.size():
		var t0: float = b * bar
		var root := Synth.midi(DICE_CHORDS[b][1])
		for q in 8:
			var t: float = t0 + eighth.call(q)
			beat.hat(t, 0.2 if q % 2 == 0 else 0.13, 0.05)
			var f := root * (2.0 if q % 4 == 3 else 1.0)
			if q != 5:
				beat.sweep(t, beat_len * 0.38, f, f, 0.45, Synth.Wave.TRI, Synth.Env.DECAY, 7.0, 0.004)
		beat.kick(t0, 1.0)
		beat.kick(t0 + eighth.call(5), 0.55)
		beat.kick(t0 + beat_len * 2.0, 1.0)
		beat.clap(t0 + beat_len, 0.5)
		beat.clap(t0 + beat_len * 3.0, 0.5)
	_save(beat, "dice_beat", 0.55, MUSIC_DIR)


## Flip Pop's soundtrack: a laid-back electric-piano groove in E flat at
## 96 bpm with a lazy boom-bap beat. Ebmaj7 Cm7 Abmaj7 Bb | Gm7 Cm7 Ab Bb.
const FLIP_BPM := 96.0
const FLIP_CHORDS := [
	[[55, 58, 62, 63], 39, [63, 67, 70, 74, 70, 67, 63, 67]],
	[[55, 58, 60, 63], 36, [60, 63, 67, 70, 67, 63, 60, 63]],
	[[55, 60, 63, 67], 44, [60, 63, 67, 72, 67, 63, 60, 63]],
	[[53, 58, 62, 65], 46, [62, 65, 70, 74, 70, 65, 62, 65]],
	[[53, 58, 62, 65], 43, [62, 65, 70, 74, 77, 74, 70, 65]],
	[[55, 58, 60, 63], 36, [63, 67, 70, 75, 70, 67, 63, 67]],
	[[56, 60, 63, 68], 44, [63, 68, 72, 75, 72, 68, 63, 68]],
	[[58, 62, 65, 70], 46, [65, 70, 74, 77, 74, 70, 65, 62]],
]


func _make_flip_music() -> void:
	var beat_len := 60.0 / FLIP_BPM
	var bar := beat_len * 4.0
	var length := bar * FLIP_CHORDS.size()

	var pad := Synth.new(length, MUSIC_RATE, true)
	for b in FLIP_CHORDS.size():
		pad.pad(b * bar, bar, FLIP_CHORDS[b][0], 1.0, 1200.0, 0.4, 0.6)
	_save(pad, "flip_pad", 0.5, MUSIC_DIR)

	# Electric piano: a soft bell with a slow decay and a gentle tine on top.
	var arp := Synth.new(length, MUSIC_RATE, true)
	for b in FLIP_CHORDS.size():
		var notes: Array = FLIP_CHORDS[b][2]
		for k in notes.size():
			var t: float = b * bar + k * beat_len * 0.5
			var f := Synth.midi(notes[k])
			var amp := 0.48 if k % 2 == 0 else 0.3
			arp.bell(t, f, 0.9, amp, 4.5, 0.35)
			arp.bell(t, f * 3.0, 0.2, amp * 0.18, 25.0, 0.2)
	arp.lowpass(4200)
	_save(arp, "flip_arp", 0.45, MUSIC_DIR)

	var beat := Synth.new(length, MUSIC_RATE, true)
	for b in FLIP_CHORDS.size():
		var t0: float = b * bar
		var root := Synth.midi(FLIP_CHORDS[b][1])
		for q in 8:
			beat.hat(t0 + q * beat_len * 0.5, 0.18 if q % 2 == 0 else 0.1, 0.04)
		for q: int in [0, 3, 4, 6]:
			var f := root * (2.0 if q == 6 else 1.0)
			beat.sweep(t0 + q * beat_len * 0.5, beat_len * 0.6, f, f, 0.45, Synth.Wave.TRI, Synth.Env.DECAY, 5.0, 0.004)
		beat.kick(t0, 1.0)
		beat.kick(t0 + beat_len * 1.5, 0.6)
		beat.kick(t0 + beat_len * 2.5, 0.8)
		beat.clap(t0 + beat_len, 0.45)
		beat.clap(t0 + beat_len * 3.0, 0.45)
	_save(beat, "flip_beat", 0.55, MUSIC_DIR)


## Mine Fleet's soundtrack: a rolling sea-shanty jig in D minor at 108 bpm,
## played in triplets, with a plucked mandolin-ish arpeggio and a stomp.
## Dm C Bb A | Dm F C A.
const FLEET_BPM := 108.0
const FLEET_CHORDS := [
	[[57, 62, 65, 50], 38, [62, 65, 69, 74, 69, 65]],
	[[55, 60, 64, 48], 36, [60, 64, 67, 72, 67, 64]],
	[[53, 58, 62, 46], 34, [58, 62, 65, 70, 65, 62]],
	[[57, 61, 64, 45], 33, [57, 61, 64, 69, 64, 61]],
	[[57, 62, 65, 50], 38, [62, 65, 69, 74, 77, 74]],
	[[57, 60, 65, 41], 41, [65, 69, 72, 77, 72, 69]],
	[[55, 60, 64, 48], 36, [64, 67, 72, 76, 72, 67]],
	[[57, 61, 64, 45], 33, [61, 64, 69, 73, 69, 64]],
]


func _make_fleet_music() -> void:
	var beat_len := 60.0 / FLEET_BPM
	var bar := beat_len * 4.0
	var length := bar * FLEET_CHORDS.size()
	var triplet := beat_len / 3.0

	var pad := Synth.new(length, MUSIC_RATE, true)
	for b in FLEET_CHORDS.size():
		pad.pad(b * bar, bar, FLEET_CHORDS[b][0], 1.0, 1300.0, 0.35, 0.6)
	_save(pad, "fleet_pad", 0.5, MUSIC_DIR)

	# A plucked arpeggio rolling in triplets, twice round each chord.
	var arp := Synth.new(length, MUSIC_RATE, true)
	for b in FLEET_CHORDS.size():
		var notes: Array = FLEET_CHORDS[b][2]
		for k in 12:
			var t: float = b * bar + k * triplet
			var f := Synth.midi(notes[k % notes.size()])
			var amp := 0.5 if k % 3 == 0 else 0.3
			arp.sweep(t, triplet * 1.6, f, f, amp, Synth.Wave.SAW, Synth.Env.DECAY, 14.0, 0.001)
	arp.lowpass(3000)
	_save(arp, "fleet_arp", 0.45, MUSIC_DIR)

	var beat := Synth.new(length, MUSIC_RATE, true)
	for b in FLEET_CHORDS.size():
		var t0: float = b * bar
		var root := Synth.midi(FLEET_CHORDS[b][1])
		for q in 12:
			beat.hat(t0 + q * triplet, 0.2 if q % 3 == 0 else 0.08, 0.04)
		for q in 4:
			var f := root * (1.5 if q % 2 == 1 else 1.0)
			beat.sweep(t0 + q * beat_len, beat_len * 0.5, f, f, 0.45, Synth.Wave.TRI, Synth.Env.DECAY, 6.0, 0.004)
			beat.kick(t0 + q * beat_len, 0.95 if q % 2 == 0 else 0.6)
		beat.clap(t0 + beat_len, 0.45)
		beat.clap(t0 + beat_len * 3.0, 0.45)
		beat.clap(t0 + beat_len * 3.0 + triplet * 2.0, 0.25)
	_save(beat, "fleet_beat", 0.55, MUSIC_DIR)


## Code Grid's soundtrack: a calm thinking groove in A major at 92 bpm, a
## music-box arpeggio over soft sevenths and a light brushed beat.
## Amaj7 F#m7 Dmaj7 E | C#m7 F#m7 Dmaj7 E.
const GRID_BPM := 92.0
const GRID_CHORDS := [
	[[56, 61, 64, 69], 45, [76, 81, 85, 88, 85, 81, 76, 80]],
	[[57, 61, 64, 66], 42, [73, 76, 81, 85, 81, 76, 73, 76]],
	[[57, 61, 62, 66], 38, [74, 78, 81, 85, 81, 78, 74, 78]],
	[[56, 59, 64, 68], 40, [76, 80, 83, 88, 83, 80, 76, 71]],
	[[56, 59, 64, 68], 37, [73, 76, 80, 85, 80, 76, 73, 76]],
	[[57, 61, 64, 66], 42, [73, 78, 81, 85, 88, 85, 81, 78]],
	[[57, 61, 62, 66], 38, [74, 78, 81, 86, 81, 78, 74, 78]],
	[[56, 59, 64, 68], 40, [76, 80, 83, 88, 92, 88, 83, 80]],
]


func _make_grid_music() -> void:
	var beat_len := 60.0 / GRID_BPM
	var bar := beat_len * 4.0
	var length := bar * GRID_CHORDS.size()

	var pad := Synth.new(length, MUSIC_RATE, true)
	for b in GRID_CHORDS.size():
		pad.pad(b * bar, bar, GRID_CHORDS[b][0], 1.0, 1100.0, 0.45, 0.6)
	_save(pad, "grid_pad", 0.5, MUSIC_DIR)

	# Music box: bright, quick-fading bells.
	var arp := Synth.new(length, MUSIC_RATE, true)
	for b in GRID_CHORDS.size():
		var notes: Array = GRID_CHORDS[b][2]
		for k in notes.size():
			var t: float = b * bar + k * beat_len * 0.5
			var amp := 0.45 if k % 2 == 0 else 0.3
			arp.bell(t, Synth.midi(notes[k]), 0.7, amp, 7.0, 0.7)
	_save(arp, "grid_arp", 0.45, MUSIC_DIR)

	var beat := Synth.new(length, MUSIC_RATE, true)
	for b in GRID_CHORDS.size():
		var t0: float = b * bar
		var root := Synth.midi(GRID_CHORDS[b][1])
		for q in 8:
			beat.hat(t0 + q * beat_len * 0.5, 0.12 if q % 2 == 0 else 0.07, 0.07)
		for q: int in [0, 3, 5]:
			beat.sweep(t0 + q * beat_len * 0.5, beat_len * 0.7, root, root, 0.42, Synth.Wave.SINE, Synth.Env.DECAY, 4.0, 0.004)
		beat.kick(t0, 0.8)
		beat.kick(t0 + beat_len * 2.5, 0.5)
		beat.clap(t0 + beat_len, 0.3)
		beat.clap(t0 + beat_len * 3.0, 0.3)
	_save(beat, "grid_beat", 0.55, MUSIC_DIR)


func _save(s: Synth, name: String, peak: float = 0.9, dir: String = SFX_DIR) -> void:
	s.normalize(peak)
	if not s.looping:
		s.smooth_edges()
	s.save(dir + name + ".wav")
	print("  ", name, "  %.2f s" % (float(s.buf.size()) / s.rate))
