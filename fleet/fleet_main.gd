extends GameScene
## Wires Mine Fleet together: the two seas (the one under fire is big, the
## other small beside it, and they swap as the turn passes), pointer and
## keyboard input (tap to fire, FLAG mode or right-click to flag), shots and
## their animations, the CPU gunner, the SONAR and FLARE powers, rounds,
## hearts, the tutorial and game over.
##
## Touch goes through Godot's mouse emulation, so one code path serves
## mouse and fingers. Keys: F toggles flag mode, S sonar, L flare.

const R := preload("res://fleet/fleet_rules.gd")
const CAMERA_PITCH := 58.0
## Screen space kept free for the HUD (left, top, right, bottom).
const MARGIN_PORTRAIT := Vector4(12, 235, 12, 240)
const MARGIN_LANDSCAPE := Vector4(270, 175, 270, 20)
const TUTORIAL_TOP := Vector2(380, 290)
## The small sea's size next to the big one, and the gap between them.
const SMALL := 0.42
const GAP := 0.9
const CPU_AIM := 0.6
const SONAR := 0
const FLARE := 1
## The tutorial's seas: the CPU's fleet to find, and yours.
const TUTORIAL_ENEMY := [".......", "...aaa.", ".......", "......d", ".......", "b..cc..", "b......"]
const TUTORIAL_HOME := ["aaa....", ".......", "....b..", "d...b..", ".......", ".cc....", "......."]
const TUTORIAL := [
	{
		"text": "Find and sink the CPU's hidden fleet! Tap a square of its sea to FIRE.",
		"goal": "fire", "target": 15,
	},
	{
		"text": "A miss shows how many ship squares TOUCH it, all 8 around. This 1 has only ONE hidden neighbour, so that's a ship: FIRE!",
		"goal": "fire", "target": 10,
	},
	{
		"text": "HIT! A hit lets you fire again. Ships are straight and never touch: sink the rest of it!",
		"goal": "sink", "ship": 0,
	},
]
const TUTORIAL_TIPS := "A miss passes the turn: then the CPU fires at YOUR fleet.\n" \
	+ "Not sure? Tap FLAG (or right-click) to mark squares you think hide ships.\n" \
	+ "Hits build a STREAK. Points fill your power bar: SONAR counts the ship squares in a row and column, FLARE lights up the water round a square.\n" \
	+ "Sink the whole fleet first to win the round. Lose one and it costs a heart!"

var game: FleetMatch
## seas[k] shows side k's fleet, as the other side sees it.
var seas: Array[SeaView] = []
var hud: VersusHud

var _hover := -1
var _flagging := false
## The power waiting for a square (-1 for none).
var _armed := -1
var _big := 1


func _ready() -> void:
	for k in 2:
		var sea := SeaView.new()
		add_child(sea)
		seas.append(sea)
	hud = VersusHud.new(["SUN  ●", "●  ICE"], FleetArt.TEAM_UI, ["SONAR", "FLARE"], "FLAG")
	add_child(hud)
	_setup(Arcade.FLEET, Sound.FLEET_MUSIC)
	for sea in seas:
		sea.impact.connect(feel.impact)
	hud.power_pressed.connect(_on_power)
	hud.action_pressed.connect(_toggle_flagging)
	hud.pause_pressed.connect(_pause)
	_begin()


# --- Hooks -------------------------------------------------------------------------------

func new_game(seed_value: int = 0) -> void:
	_generation += 1
	_busy = false
	_flagging = false
	_armed = -1
	game = FleetMatch.new(seed_value, not _two_players)
	game.start()
	_deal()
	hud.reset(game.vs_cpu, records.best())
	_set_fever(false)
	Sound.set_intensity(0, false)
	_start_turn()


func _tutorial() -> Array:
	return TUTORIAL


func _tutorial_tips() -> String:
	return TUTORIAL_TIPS


func _load_tutorial_step(step: Dictionary) -> void:
	if _tutorial_step == 0:
		game.set_fleets(R.fleet_from_rows(TUTORIAL_HOME), R.fleet_from_rows(TUTORIAL_ENEMY))
		_deal()
	game.turn = 0
	_start_turn()
	_point_tutorial()


func _cancel() -> bool:
	if _armed >= 0:
		_disarm()
		return true
	return false


func _record() -> Array:
	return [game.scores[0], game.round, game.total_turns]


func _fever_changed(on: bool) -> void:
	for sea in seas:
		sea.set_fever(on)


func _layout() -> void:
	var portrait := Stage.fit_ui(get_window())
	_place_seas(portrait, false)
	var box := seas[0].bounds().merge(seas[1].bounds())
	_fit(box.position, box.end, MARGIN_PORTRAIT, MARGIN_LANDSCAPE, TUTORIAL_TOP, CAMERA_PITCH)
	hud.set_landscape(not portrait)


## Puts the sea under fire big in the middle and the other small beside it
## (to the right, or below on a tall screen), sliding them if `animate`.
func _place_seas(portrait: bool, animate: bool) -> void:
	var big := seas[_big]
	var small := seas[1 - _big]
	var half := game.n * FleetArt.CELL * 0.5
	var small_half := half * SMALL
	var spot := Vector3(half + GAP + small_half, 0, -half + small_half + 0.4) if not portrait \
		else Vector3(0, 0, half + GAP + 0.6 + small_half)
	if not animate:
		big.position = Vector3.ZERO
		big.scale = Vector3.ONE
		small.position = spot
		small.scale = Vector3.ONE * SMALL
		return
	for pair: Array in [[big, Vector3.ZERO, 1.0], [small, spot, SMALL]]:
		var sea: SeaView = pair[0]
		var tw := sea.create_tween().set_parallel(true)
		tw.tween_property(sea, "position", pair[1], 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(sea, "scale", Vector3.ONE * float(pair[2]), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


## Fresh seas for the round, with no animation.
func _deal() -> void:
	var names := ["YOUR FLEET", "CPU FLEET"] if game.vs_cpu else ["SUN FLEET", "ICE FLEET"]
	for k in 2:
		seas[k].setup(game.n, _covered(k), k, names[k], FleetArt.team_color(k))
		_show_sea(k)
	_big = 1 - game.turn
	_layout()


## Against the CPU your own fleet is open to you; otherwise fleets stay hidden.
func _covered(k: int) -> bool:
	return k == 1 or not game.vs_cpu


func _show_sea(k: int) -> void:
	seas[k].show_state(game.fleets[k], game.seen[1 - k], game.flags[1 - k], game.sonar[1 - k], not _covered(k))


# --- Input ---------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_back()
		elif _playing() and event.keycode == KEY_F:
			_toggle_flagging()
		elif _playing() and event.keycode == KEY_S:
			_on_power(SONAR)
		elif _playing() and event.keycode == KEY_L:
			_on_power(FLARE)
		return
	if not _playing():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_press(event.position, _flagging)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_on_press(event.position, true)
	elif event is InputEventMouseMotion:
		_on_move(event.position)


func _can_input() -> bool:
	return not _busy and game.is_running() and not game.is_cpu_turn()


## The square of the sea under fire at a screen point, or -1.
func _square_at(pos: Vector2) -> int:
	var sea := seas[_big]
	var height := FleetArt.COVER_HEIGHT if sea.covered else 0.0
	return sea.world_to_index(Stage.pointer_on_plane(camera, pos, height))


func _on_press(pos: Vector2, flag: bool) -> void:
	if not _can_input():
		return
	var i := _square_at(pos)
	if i < 0:
		return
	if _armed >= 0:
		_use_power(_armed, i)
		return
	if flag:
		if _tutorial_step >= 0:
			hud.hint("Flags come later: tap to fire!")
			return
		if game.toggle_flag(i):
			seas[_big].set_flag(i, game.flags[game.turn].has(i))
		return
	if not game.can_fire(i):
		hud.hint("Already fired there: pick a covered square")
		Sound.play("invalid")
		feel.impact(0.1)
		return
	if game.flags[game.turn].has(i):
		hud.hint("That square is flagged: tap FLAG and unflag it to fire there")
		Sound.play("invalid")
		return
	if not _tutorial_allows(i):
		return
	_fire(i)


func _on_move(pos: Vector2) -> void:
	if not _can_input():
		return
	var i := _square_at(pos)
	if i == _hover:
		return
	_hover = i
	seas[_big].set_hover(i if game.can_fire(i) or _armed >= 0 else -1)


func _toggle_flagging() -> void:
	if not _can_input():
		return
	if _tutorial_step >= 0:
		hud.hint("Flags come later: tap to fire!")
		return
	_flagging = not _flagging
	_disarm()
	_refresh()
	hud.hint("Tap squares to flag or unflag them" if _flagging else "Tap a covered square to fire")


func _who(side: int) -> String:
	if game.vs_cpu:
		return "You" if side == 0 else "The CPU"
	return FleetArt.TEAM_NAMES[side]


# --- Tutorial ----------------------------------------------------------------------------------

func _tutorial_allows(i: int) -> bool:
	if _tutorial_step < 0:
		return true
	var step: Dictionary = TUTORIAL[_tutorial_step]
	var ok: bool = i == step.target if step.goal == "fire" else game.fleets[1][i] == step.ship
	if not ok:
		hud.hint("Tap the square the arrow points at")
	return ok


## Points at the next square the tutorial wants.
func _point_tutorial() -> void:
	var step: Dictionary = TUTORIAL[_tutorial_step]
	if step.goal == "fire":
		seas[1].show_target(step.target)
		return
	for c in R.ship_cells(game.fleets[1], step.ship):
		if game.seen[0][c] == R.UNKNOWN:
			seas[1].show_target(c)
			return


func _tutorial_after(result: Dictionary) -> void:
	var step: Dictionary = TUTORIAL[_tutorial_step]
	game.turn = 0
	if step.goal == "sink" and result.sunk != step.ship:
		_busy = false
		_start_turn()
		_point_tutorial()
		return
	await _wait(0.4)
	_busy = false
	if _mode == Mode.TUTORIAL:
		_advance_tutorial()


# --- Turns -----------------------------------------------------------------------------------

func _start_turn() -> void:
	_hover = -1
	_refresh()
	var side := game.turn
	_set_fever(game.is_fever(side) and (side == 0 or not game.vs_cpu))
	for sea in seas:
		sea.set_tint(Color(FleetArt.team_color(side), 0.5))
	if game.is_cpu_turn():
		hud.set_turn("CPU TAKING AIM", FleetArt.team_color(1), true)
		if _mode == Mode.PLAY:
			_cpu_turn()
		return
	hud.set_turn("YOUR SHOT" if game.vs_cpu else "%s FIRES" % FleetArt.TEAM_NAMES[side], FleetArt.team_color(side))
	if _tutorial_step < 0 and _mode == Mode.PLAY and not _flagging:
		hud.hint("Tap a covered square to fire")


## Swaps which sea is big when the side under fire changes.
func _swap_to(side: int) -> void:
	var target := 1 - side
	if target == _big:
		return
	_big = target
	Sound.play("whoosh", 0.9, -4.0)
	_place_seas(not hud.is_landscape(), true)
	await _wait(0.5)


func _refresh() -> void:
	hud.show_scores(game.scores, [game.meter_fill(0), game.meter_fill(1)])
	hud.show_round(game.round, game.hearts, game.round_wins)
	var shown := game.turn if not game.vs_cpu else 0
	hud.show_streak(game.streak[shown], game.streak_mult(shown), game.is_fever(shown))
	var left := [game.afloat(0).size(), game.afloat(1).size()]
	if game.vs_cpu:
		hud.set_info("CPU SHIPS %d  ·  YOURS %d" % [left[1], left[0]])
	else:
		hud.set_info("SHIPS  SUN %d  ·  ICE %d" % [left[0], left[1]])
	var mine := _can_input()
	var side := game.turn if not game.is_cpu_turn() else 0
	var charges := game.charges[side]
	hud.style_power(SONAR, "SONAR  x%d" % charges, mine and game.can_use_power(), Color("3fd8f0"), _armed == SONAR)
	hud.style_power(FLARE, "FLARE  x%d" % charges, mine and game.can_use_power(), Color("ff8a1f"), _armed == FLARE)
	hud.style_action("FLAG: ON" if _flagging else "FLAG", mine, FleetArt.FLAG if _flagging else Color("8f5bff"))


func _fire(i: int) -> void:
	_busy = true
	_disarm()
	seas[_big].set_hover(-1)
	hud.hint("")
	var result := game.fire(i)
	if result.is_empty():
		_busy = false
		return
	var generation := _generation
	var sea := seas[1 - result.side]
	sea.note_base = clampi(game.streak[result.side] - 1, 0, 6)
	_refresh()
	await sea.animate_fire(result, game.fleets[1 - result.side])
	if generation != _generation:
		return
	_announce(result)
	if _mode == Mode.TUTORIAL:
		await _tutorial_after(result)
		return
	await _after(result)


func _announce(result: Dictionary) -> void:
	var side: int = result.side
	var mine := side == 0 or not game.vs_cpu
	var sea := seas[1 - side]
	if result.sunk >= 0:
		var length: int = result.sunk_cells.size()
		var word := "SUNK!" if length < 4 else ("BIG ONE SUNK!" if length == 4 else "FLAGSHIP SUNK!")
		if mine:
			hud.toast(word, Palette.GOLD, 1.3 + 0.05 * length)
		else:
			hud.toast("%s SANK YOUR SHIP" % _who(side).to_upper() if game.vs_cpu else "%s SANK A SHIP" % _who(side),
				FleetArt.team_color(side), 1.2)
	elif result.hit:
		hud.toast("HIT!" if mine else "%s HIT YOU" % _who(side).to_upper(), Palette.HOT if mine else FleetArt.team_color(side), 1.15)
	elif result.opened.size() >= 8 and mine:
		hud.toast("CALM SEAS x%d" % result.opened.size(), Color("6fd6ff"), 1.1)
	if mine and result.points > 0:
		var c := Palette.HOT if result.fever else Palette.GOLD
		sea.float_text("+%d" % result.points, result.at, c, 90 + mini(result.points, 1500) / 15)
	if mine and result.fever and not _fever_on:
		hud.toast("FEVER!", Palette.HOT, 1.4)
		Sound.play("fever")
		Sound.duck(5.0, 0.8)
	if mine:
		Sound.set_intensity(result.streak, result.fever)
	for k in result.charges_earned:
		if mine:
			hud.toast("+ POWER", VersusHud.POWER_COLOR)
			Sound.play_later(0.12 * k, "coin")


## After a shot: the round's end, another shot, or the other side's turn.
func _after(result: Dictionary) -> void:
	_refresh()
	if result.round_over:
		await _round_over(result)
		return
	if not result.again:
		var who := game.turn
		hud.toast("MISS!" if game.vs_cpu and who == 1 else ("THE CPU MISSED" if game.vs_cpu else "%s'S TURN" % FleetArt.TEAM_NAMES[who]),
			Palette.TEXT if who == 1 or not game.vs_cpu else FleetArt.team_color(0), 0.9)
		await _wait(0.5)
		await _swap_to(who)
	_busy = false
	_start_turn()


# --- The CPU ---------------------------------------------------------------------------------

func _cpu_turn() -> void:
	_busy = true
	var generation := _generation
	await _wait(CPU_AIM)
	if generation != _generation:
		return
	var cfg := FleetMatch.cpu_config(game.round)
	var nums := R.visible_numbers(game.fleets[0], game.seen[1], game.n)
	var i := FleetAI.choose(game.seen[1], nums, game.n, game.afloat(0), cfg, game.rng)
	if i < 0:
		return
	seas[0].set_hover(i)
	await _wait(0.35)
	if generation != _generation:
		return
	_fire(i)


# --- Rounds and the end ---------------------------------------------------------------------

func _round_over(result: Dictionary) -> void:
	var generation := _generation
	var winner: int = result.winner
	hud.clear_turn()
	_set_fever(false)
	Sound.set_intensity(0, false)
	await _wait(0.6)
	if generation != _generation:
		return
	hud.toast("FLEET DESTROYED!", Palette.GOLD if winner == 0 or not game.vs_cpu else Palette.HOT, 1.5)
	seas[winner].dim_ships()
	# Show both fleets for the end of the round.
	seas[1 - winner].show_state(game.fleets[1 - winner], game.seen[winner], {}, {}, true)
	if winner == 0 or not game.vs_cpu:
		seas[1 - winner].celebrate()
		Sound.play("win")
		Sound.duck(8.0, 1.5)
	else:
		Sound.play("game_over")
	await _wait(1.4)
	if generation != _generation:
		return
	if game.vs_cpu and winner == 0:
		hud.toast("ROUND CLEAR!  +%s" % UI.thousands(result.round_bonus), Palette.GOLD, 1.3)
		Sound.play("level_up")
	elif game.vs_cpu:
		hud.toast("THE CPU WINS THE ROUND", FleetArt.team_color(1), 1.2)
		if not game.game_over:
			hud.toast("-1 ♥   %d LEFT" % game.hearts, Palette.HOT, 1.3)
			Sound.play("crack", 0.8)
	else:
		hud.toast("%s TAKES THE ROUND" % FleetArt.TEAM_NAMES[winner], FleetArt.team_color(winner), 1.3)
	_refresh()
	await _wait(1.6)
	if generation != _generation:
		return
	if game.game_over:
		_end_match("OUT OF HEARTS" if game.vs_cpu else "%s WINS!" % FleetArt.TEAM_NAMES[winner])
		return
	var replay := game.vs_cpu and winner != 0
	var size_before := game.n
	game.next_round()
	Sound.play("deal")
	_deal()
	for sea in seas:
		sea.scale = sea.scale * 0.01
		sea.create_tween().tween_property(sea, "scale", sea.scale * 100.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	hud.toast(("ROUND %d AGAIN" if replay else "ROUND %d") % game.round, Palette.TEXT, 1.4)
	if game.n != size_before:
		hud.toast("WIDER SEA!", Palette.GOLD, 1.2)
	elif not replay and FleetMatch.sea_setup(game.round).ships.size() > FleetMatch.sea_setup(game.round - 1).ships.size():
		hud.toast("BIGGER FLEETS!", Palette.GOLD, 1.2)
	await _wait(0.4)
	_busy = false
	_start_turn()


func _end_match(title: String) -> void:
	_mode = Mode.OVER
	_busy = true
	hud.clear_turn()
	if game.vs_cpu:
		var accuracy := roundi(100.0 * game.hits / maxi(game.shots, 1))
		var stats := "Round %d   ·   Rounds won %d   ·   Best streak %d\nShips sunk %d   ·   Shots %d   ·   Accuracy %d%%" % [
			game.round, game.rounds_won, game.best_streak, game.ships_sunk, game.shots, accuracy]
		menus.show_game_over(title, game.scores[0], stats, records, records.best(), "Rd")
	else:
		var stats := "SUN %d  –  %d ICE   ·   %d rounds\nSUN %s   ·   ICE %s" % [game.round_wins[0], game.round_wins[1],
			game.round, UI.thousands(game.scores[0]), UI.thousands(game.scores[1])]
		menus.show_game_over(title, 0, stats, null, 0, "Rd", "REMATCH")


# --- Powers -----------------------------------------------------------------------------------

func _on_power(which: int) -> void:
	if not _can_input():
		return
	if _tutorial_step >= 0:
		hud.hint("Powers come later!")
		return
	if _armed == which:
		_disarm()
		return
	if not game.can_use_power():
		return
	_armed = which
	_flagging = false
	_refresh()
	hud.hint("Tap a square: SONAR counts ship squares in its row and column" if which == SONAR
		else "Tap a square: FLARE lights up the water around it")
	Sound.play("click", 1.2)


func _disarm() -> void:
	if _armed < 0:
		return
	_armed = -1
	if game != null:
		_refresh()


func _use_power(which: int, i: int) -> void:
	_armed = -1
	_busy = true
	var sea := seas[_big]
	sea.set_hover(-1)
	if which == SONAR:
		var counts := game.use_sonar(i)
		sea.show_sonar(i, counts)
		hud.toast("SONAR!", Color("3fd8f0"), 1.1)
		hud.hint("Row: %d ship squares  ·  Column: %d" % [counts.x, counts.y])
		await _wait(0.5)
	else:
		var opened := game.use_flare(i)
		hud.toast("FLARE!", Color("ff8a1f"), 1.1)
		Sound.play("upgrade", 1.1)
		sea.fx.beam(sea.cell_to_local(i), Vector3(3, 3.5, 3), Color("ff8a1f"), 0.7)
		await sea.animate_open(opened, game.fleets[1 - game.turn])
		hud.hint("%d squares of water lit up" % opened.size())
	_busy = false
	_refresh()


# --- Developer helpers (used by tools/dev_shot.gd) ------------------------------------------

func debug_summary() -> String:
	return "round %d  score %d  hearts %d  turns %d  winner %d  mode %d  afloat %d-%d" % [
		game.round, game.scores[0], game.hearts, game.total_turns, game.winner, _mode,
		game.afloat(0).size(), game.afloat(1).size()]


## Plays the player's shots with the CPU's sharpest gunner, through the
## animated path (both sides with two players).
func debug_autoplay(turns: int) -> void:
	var cfg := {"read": 1.0, "blunder": 0.0}
	for t in turns:
		while _busy or game.is_cpu_turn():
			if game.game_over or _mode == Mode.OVER:
				break
			await get_tree().process_frame
		if game.game_over or _mode == Mode.OVER:
			break
		if not game.is_running():
			await get_tree().process_frame
			continue
		var side := game.turn
		var i := FleetAI.choose(game.seen[side], R.visible_numbers(game.fleets[1 - side], game.seen[side], game.n),
			game.n, game.afloat(1 - side), cfg, game.rng)
		await _fire(i)
	while _busy and not (game.game_over and _mode == Mode.OVER):
		await get_tree().process_frame


func debug_round(r: int) -> void:
	game.round = r
	game.start_round()
	_deal()
	_start_turn()


func debug_game_over() -> void:
	game.scores[0] = 15420
	game.round = 4
	game.rounds_won = 3
	game.hearts = 0
	game.shots = 61
	game.hits = 30
	game.ships_sunk = 14
	_end_match("OUT OF HEARTS")


## Mid-round: some water open, a flag and a hover.
func debug_hover() -> void:
	var nums := R.visible_numbers(game.fleets[1], game.seen[0], game.n)
	var i := FleetAI.choose(game.seen[0], nums, game.n, game.afloat(1), {"read": 1.0, "blunder": 0.0}, game.rng)
	seas[1].set_hover(i)
	for c in game.n * game.n:
		if game.seen[0][c] == R.UNKNOWN and c != i:
			game.toggle_flag(c)
			seas[1].set_flag(c, true)
			break


## One shot through a real click.
func debug_drag() -> void:
	while _busy or game.is_cpu_turn():
		await get_tree().process_frame
	var shots := game.turns
	var i := game.n * game.n / 2
	while not game.can_fire(i):
		i += 1
	await _sim_tap_world(seas[_big].cell_to_world(i) + Vector3(0, FleetArt.COVER_HEIGHT, 0))
	await _idle()
	print("debug_drag: fired = ", game.turns > shots)


## Sinks a ship through clicks.
func debug_mate() -> void:
	var cells := R.ship_cells(game.fleets[1], 0)
	for c in cells:
		while _busy:
			await get_tree().process_frame
		await _sim_tap_world(seas[1].cell_to_world(c) + Vector3(0, FleetArt.COVER_HEIGHT, 0))
	await _idle()
	print("debug_mate: ships left ", game.afloat(1).size(), " of ", game.lengths.size())


## SONAR then FLARE, through clicks.
func debug_upgrade() -> void:
	game.charges[0] = 2
	_refresh()
	var c := game.n * 2 + 2
	await _sim_tap_button(hud.powers[SONAR])
	await _sim_tap_world(seas[1].cell_to_world(c) + Vector3(0, FleetArt.COVER_HEIGHT, 0))
	await _idle()
	await _sim_tap_button(hud.powers[FLARE])
	await _sim_tap_world(seas[1].cell_to_world(c + game.n * 3 + 3) + Vector3(0, FleetArt.COVER_HEIGHT, 0))
	await _idle()
	print("debug_upgrade: sonar ", game.sonar[0], ", charges ", game.charges[0])


func debug_tutorial() -> void:
	_start_tutorial()
	await _wait(0.6)
	var taps := [15, 10, 11, 12]
	for c: int in taps:
		await _sim_tap_world(seas[1].cell_to_world(c) + Vector3(0, FleetArt.COVER_HEIGHT, 0))
		await _wait(0.2)
		await _idle()
		print("debug_tutorial: after firing at %d the tutorial is on step %d" % [c, _tutorial_step + 1])
	print("debug_tutorial: end card shown = ", menus.is_open())


## A big calm-sea opening, for the screenshot.
func debug_merge() -> void:
	var best := -1
	var most := 0
	for c in game.n * game.n:
		if game.fleets[1][c] == R.SEA and R.number(game.fleets[1], game.n, c) == 0:
			var s := game.seen[0].duplicate()
			var opened := R.open_water(game.fleets[1], s, game.n, [c]).size()
			if opened > most:
				most = opened
				best = c
	if best >= 0:
		await _fire(best)
