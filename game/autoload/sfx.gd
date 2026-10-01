extends Node
## Sound. Two layers:
##  • Generic synthetic WAVs (tools/gen_sfx.gd): impact clangs/thuds/bounces,
##    buzzer, score pops — always loaded.
##  • Per-set tables loaded on demand from the active cosmetic sets: the HOOP
##    owns make / miss and may override rim / board contacts; the BALL owns
##    floor bounces (and later pickup / release). Selecting a set loads its
##    clips and releases the previous set's, so only the active bundles are in
##    memory. Picks never repeat the previous clip. Presentation-only RNG.

const POOL := 8
## Recorded clips peak around −10 dBFS; lift them toward the synthetic set.
const MAKE_GAIN_DB := 0.0
const MISS_GAIN_DB := -1.0
## A rattling ball can hit the rim several times; play the miss clip once per burst.
const MISS_RATE_LIMIT_S := 0.6

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _streams := {}          # generic
var _hoop := {}             # "make"/"miss"/"rim"/"board" → Array[AudioStream]
var _ball := {}             # "bounce"/"pickup"/"release" → Array[AudioStream]
## Recorded contact sounds that belong to the WORLD rather than to any cosmetic
## set — a pole sounds like a pole whichever hoop is bolted to it. Same shape as
## _hoop/_ball so it can use the same non-repeating picker.
var _generic := {}          # "pole" → Array[AudioStream]

## A typed Array, not a PackedStringArray: a constructor call is not a constant
## expression, so PackedStringArray([...]) cannot be a const.
const POLE_CLIPS: Array[String] = [
	"res://assets/audio/fx/pole_sound_1.wav",
	"res://assets/audio/fx/pole_sound_2.wav",
	"res://assets/audio/fx/pole_sound_3.wav",
]
var _hoop_id := ""
var _ball_id := ""
var _rng := RandomNumberGenerator.new()
var _last := {}             # table key → last index played
var _last_miss_usec := -1_000_000


func _ready() -> void:
	_rng.randomize()
	for name_ in [
		"rim_clang_0", "rim_clang_1", "rim_clang_2",
		"board_thud_0", "board_thud_1", "board_thud_2",
		"bounce_0", "bounce_1", "bounce_2",
		"swish", "net", "chain_rattle_0", "chain_rattle_1", "score_pop", "score_pop_swish", "buzzer",
		"ice_freeze", "ice_crack_0", "ice_crack_1", "ice_shatter",
		"peggy_press", "peggy_servo", "peggy_ticket", "peggy_peg_0", "peggy_peg_1", "peggy_peg_2",
		"peggy_win", "peggy_jackpot", "match_loss",
		"fx/fire_burst", "fx/ice_form", "fx/ice_break", "fx/ice_swish", "fx/fire_out",
	]:
		_streams[name_] = load("res://assets/audio/%s.wav" % name_)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.push_back(p)


# ---- cosmetic sets --------------------------------------------------------------


static func _load_list(paths: PackedStringArray) -> Array:
	var out := []
	for p in paths:
		var s := load(p)
		if s != null:
			out.push_back(s)
	return out


var _net_kind := "nylon"


## Load a hoop set's sounds (replacing the previous hoop's).
func load_hoop_set(set: HoopSet) -> void:
	_hoop = {}
	_hoop_id = ""
	_net_kind = "nylon"
	if set == null:
		return
	_net_kind = set.net_kind
	_hoop = {
		"make": _load_list(set.make_clips),
		"miss": _load_list(set.miss_clips),
		"rim": _load_list(set.rim_clips),
		"board": _load_list(set.board_clips),
	}
	_hoop_id = set.id
	for k in ["make", "miss", "rim", "board"]:
		_last.erase("hoop:" + k)


## Load a ball set's sounds (replacing the previous ball's).
func load_ball_set(set: BallSet) -> void:
	_ball = {}
	_ball_id = ""
	if set == null:
		return
	_ball = {
		"bounce": _load_list(set.bounce_clips),
		"pickup": _load_list(set.pickup_clips),
		"release": _load_list(set.release_clips),
	}
	_ball_id = set.id
	for k in ["bounce", "pickup", "release"]:
		_last.erase("ball:" + k)


func hoop_id() -> String:
	return _hoop_id


## The live hoop's net: "nylon" or "chain" (the links rattle under rim hits).
func net_kind() -> String:
	return _net_kind


func ball_id() -> String:
	return _ball_id


func hoop_clip_count(kind: String) -> int:
	return _hoop.get(kind, []).size()


func ball_clip_count(kind: String) -> int:
	return _ball.get(kind, []).size()


## Where a contact sound comes from: "hoop", "ball" or "generic".
## "pole" is always "generic" — it is world geometry, not a cosmetic set.
func contact_source(kind: String) -> String:
	match kind:
		"rim", "board":
			return "hoop" if _hoop.get(kind, []).size() == 3 else "generic"
		"floor":
			return "ball" if not _ball.get("bounce", []).is_empty() else "generic"
	return "generic"


# ---- ambience (per-area looping background layers) ------------------------------

## Layers live under a node that keeps processing while the game is paused, so
## the beach stays alive behind the pause overlay. They bypass the SFX pool and
## the gain_db duck (the opponent's PiP must not quiet the waves).
var _amb: Node
var _amb_id := ""
var _amb_players: Array[AudioStreamPlayer] = []
var _amb_gains: Array[float] = []
var _amb_tween: Tween
var _amb_stopping := false
var _amb_rng := RandomNumberGenerator.new()


func _amb_root() -> Node:
	if _amb == null:
		_amb = Node.new()
		_amb.name = "Ambience"
		_amb.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_amb)
	return _amb


## Play an arena's ambient layers (looping, faded in). The same arena again is
## a no-op — or cancels a pending fade-out — so hopping between that area's
## dashboard and its heats never gaps. A set with no clips silences everything.
func start_ambience(set: ArenaSet) -> void:
	if set == null or set.ambient_clips.is_empty():
		stop_ambience()
		return
	start_layers(set.id, set.ambient_clips, set.ambient_gains_db, set.ambient_fade_s)


## A music loop on the same channel (the title): an area's ambience replaces it.
func start_music(id: String, clip: String, gain_db: float, fade_s := 1.0) -> void:
	start_layers(id, PackedStringArray([clip]), PackedFloat32Array([gain_db]), fade_s)


## The generic entry point: looping layers keyed by `id`.
func start_layers(id: String, clips: PackedStringArray, gains_db: PackedFloat32Array, fade_s: float) -> void:
	if clips.is_empty():
		stop_ambience()
		return
	if id == _amb_id and not _amb_players.is_empty():
		if _amb_stopping:
			_amb_stopping = false
			_amb_fade_to_gains(fade_s)
		return
	_amb_kill_layers()
	_amb_id = id
	var root := _amb_root()
	for i in clips.size():
		var stream: AudioStream = load(clips[i])
		if stream == null:
			continue
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamWAV:
			var w := stream as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		elif stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		var p := AudioStreamPlayer.new()
		p.name = "Layer%d" % i
		p.stream = stream
		p.volume_db = -60.0
		root.add_child(p)
		var length := stream.get_length()
		p.play(_amb_rng.randf() * length if length > 0.0 else 0.0)
		_amb_players.push_back(p)
		_amb_gains.push_back(gains_db[i] if i < gains_db.size() else 0.0)
	_amb_fade_to_gains(fade_s)


func _amb_fade_to_gains(seconds: float) -> void:
	if _amb_tween != null:
		_amb_tween.kill()
	_amb_tween = _amb_root().create_tween().set_parallel(true)
	for i in _amb_players.size():
		_amb_tween.tween_property(_amb_players[i], "volume_db", _amb_gains[i], seconds)


## Fade the layers out and drop them (cancelled if the same area starts again
## before the fade ends).
func stop_ambience(fade_s := 1.0) -> void:
	stop_track(fade_s)
	if _amb_players.is_empty():
		_amb_id = ""
		return
	_amb_stopping = true
	if _amb_tween != null:
		_amb_tween.kill()
	_amb_tween = _amb_root().create_tween().set_parallel(true)
	for p in _amb_players:
		_amb_tween.tween_property(p, "volume_db", -60.0, fade_s)
	_amb_tween.set_parallel(false)
	_amb_tween.tween_callback(func() -> void:
		if _amb_stopping:
			_amb_kill_layers()
	)


func _amb_kill_layers() -> void:
	for p in _amb_players:
		p.stop()
		p.queue_free()
	_amb_players.clear()
	_amb_gains.clear()
	_amb_id = ""
	_amb_stopping = false


# ---- track channel (an in-world radio, beside the ambience) ----------------------

var _track: AudioStreamPlayer
var _track_id := ""
var _track_tween: Tween


## Play a looping track on its own channel (crossfades from the current one).
func play_track(id: String, clip: String, gain_db: float, fade_s := 0.6) -> void:
	if id == _track_id and _track != null:
		return
	var stream: AudioStream = load(clip)
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	stop_track(fade_s)
	var p := AudioStreamPlayer.new()
	p.name = "Track"
	p.stream = stream
	p.volume_db = -60.0
	_amb_root().add_child(p)
	p.play()
	_track = p
	_track_id = id
	_track_tween = _amb_root().create_tween()
	_track_tween.tween_property(p, "volume_db", gain_db, fade_s)


## Fade the track out and drop it.
func stop_track(fade_s := 0.6) -> void:
	_track_id = ""
	if _track == null:
		return
	var old := _track
	_track = null
	var tw := _amb_root().create_tween()
	tw.tween_property(old, "volume_db", -60.0, fade_s)
	tw.tween_callback(func() -> void:
		# The player can be gone by now (a second stop, or a teardown).
		if is_instance_valid(old):
			old.stop()
			old.queue_free())


func track_id() -> String:
	return _track_id


## The area whose layers are playing ("" while fading out or silent).
func ambience_id() -> String:
	return "" if _amb_stopping else _amb_id


func ambience_layer_count() -> int:
	return _amb_players.size()


func ambience_stopping() -> bool:
	return _amb_stopping


# ---- playback -------------------------------------------------------------------


## Extra gain applied to every clip started while set (the heat screen ducks
## the opponent's court to this while dispatching its events, then restores).
var gain_db := 0.0

## The live rim's rigidity (SimGeometry.rim_rigidity): 1.0 = the arcade cage.
## A stiffer rim rings TIGHTER and QUIETER — pitch rises as sqrt(r), the same
## law as its wobble rate, and level falls as 1/r, the same law as its swing.
## Set by the screen that owns the court; only the rim scales, because only the
## rim's restitution varies (the backboard keeps SimConstants everywhere).
var rim_rigidity := 1.0


func _play_stream(stream: AudioStream, volume_db := 0.0, pitch := 1.0) -> void:
	volume_db += gain_db
	if stream == null or _players.is_empty():
		return   # nothing to play, or a headless instance without its player pool
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = stream
	p.volume_db = volume_db
	# ALWAYS assign, never only when pitched: the pool is reused round-robin, so
	# a pitch left on a player would ride the next, unrelated clip to reach it.
	p.pitch_scale = pitch
	p.play()


func _play(name_: String, volume_db := 0.0, pitch := 1.0) -> void:
	_play_stream(_streams.get(name_), volume_db, pitch)


# ---- PEGGY (docs/LOCKER.md) --------------------------------------------------------

var _servo: AudioStreamPlayer
var _servo_tween: Tween


func peggy_press() -> void:
	_play("peggy_press", -2.0)


func peggy_ticket() -> void:
	_play("peggy_ticket", -4.0)


func peggy_peg(variant: int, pitch := 1.0) -> void:
	_play("peggy_peg_%d" % (variant % 3), -6.0, pitch)


func peggy_win() -> void:
	_play("peggy_win", -3.0)


func peggy_jackpot() -> void:
	_play("peggy_jackpot", -1.0)


## The match-end page's loss sting.
func match_loss() -> void:
	_play("match_loss", -3.0)


## The carriage's servo whine, looped while the aim moves.
func peggy_servo_start() -> void:
	var stream: AudioStreamWAV = _streams.get("peggy_servo")
	if stream == null:
		return
	if _servo == null:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
		_servo = AudioStreamPlayer.new()
		_servo.name = "PeggyServo"
		_servo.stream = stream
		add_child(_servo)
	if _servo_tween != null:
		_servo_tween.kill()
		_servo_tween = null
	_servo.volume_db = -10.0 + gain_db
	if not _servo.playing:
		_servo.play()


func peggy_servo_stop(fade := 0.08) -> void:
	if _servo == null or not _servo.playing:
		return
	if _servo_tween != null:
		_servo_tween.kill()
	_servo_tween = create_tween()
	_servo_tween.tween_property(_servo, "volume_db", -40.0, fade)
	_servo_tween.tween_callback(_servo.stop)


func peggy_servo_playing() -> bool:
	return _servo != null and _servo.playing


## Random index in [0, count) that differs from `last` (when count > 1).
func _pick(count: int, last: int) -> int:
	if count <= 1:
		return 0
	var idx := _rng.randi_range(0, count - 2)
	if idx >= last:
		idx += 1
	return idx


## Play a random, non-repeating clip from a set table. False if the table is empty.
func _play_from(table: Dictionary, prefix: String, kind: String, volume_db := 0.0, pitch := 1.0) -> bool:
	var clips: Array = table.get(kind, [])
	if clips.is_empty():
		return false
	var key := prefix + ":" + kind
	var idx := _pick(clips.size(), _last.get(key, -1))
	_last[key] = idx
	_play_stream(clips[idx], volume_db, pitch)
	return true


## Fill the world-contact table, on first use rather than in _ready().
##
## _ready() is NOT safe to assume here: a headless SceneTree script — the test
## runner is one — calls into the autoloads from _initialize(), which happens
## before any autoload's _ready() has fired. Loading on demand makes Sfx correct
## whoever reaches it first.
##
## _load_list drops whatever failed to load, so a missing clip leaves the table
## short (or empty) and contact() falls back to the synthetic thud, rather than
## holding a null and playing silence.
func _ensure_generic() -> void:
	if not _generic.has("pole"):
		_generic["pole"] = _load_list(PackedStringArray(POLE_CLIPS))


## Contact event from the sim: kind ∈ rim | board | floor, speed in m/s.
func contact(kind: String, speed: float) -> void:
	var intensity := minf(speed / 7.0, 1.0)
	var variant := clampi(int(intensity * 3.0), 0, 2)
	# Gentle volume ride on top of the baked variants.
	var vol := lerpf(-6.0, 0.0, intensity)
	match kind:
		"wall":
			# Chain-link / concrete: a softer rattle. This is the ONLY user of the
			# synthetic clang now — the rim itself plays the hoop's recorded clips
			# (see miss_on_rim), so it no longer borrows a rim hit to get here.
			var wall_i := minf(speed * 0.5 / 7.0, 1.0)
			_play("rim_clang_%d" % clampi(int(wall_i * 3.0), 0, 2), lerpf(-6.0, 0.0, wall_i))
			return
		"pole":
			# Recorded pole hits, a random one each time and never the same
			# twice running. Falls back to the board thud the way "floor" falls
			# back to the synthetic bounces.
			_ensure_generic()
			if not _play_from(_generic, "generic", "pole", vol):
				contact("board", speed)
			return
		"rim":
			# No synthetic fallback: a hoop that names its own rim_clips gets
			# them, and every other rim is carried entirely by the recorded miss
			# clip that miss_on_rim() fires on the same contact. Doubling a
			# generated clang on top of a real recording only muddied it.
			if contact_source("rim") == "hoop":
				_play_stream(_hoop["rim"][variant], vol + rim_level_db(), rim_pitch())
			# A chain net jangles on every rim hit — its most recognisable sound.
			if _net_kind == "chain":
				_play("chain_rattle_%d" % (variant % 2), vol - 6.0)
		"board":
			if contact_source("board") == "hoop":
				_play_stream(_hoop["board"][variant], vol)
			else:
				_play("board_thud_%d" % variant, vol)
		"floor":
			# The ball's own bounces: any number of clips, a random one each hit
			# (never the same twice running), like the hoop's swishes.
			if not _play_from(_ball, "ball", "bounce", vol):
				_play("bounce_%d" % variant, vol)


## A made shot: the hoop's make clip (falls back to the synthetic swish).
func make() -> void:
	if not _play_from(_hoop, "hoop", "make", MAKE_GAIN_DB):
		_play("swish")


## Level and pitch offsets for the live rim's rigidity. A stiffer ring rings
## TIGHTER and QUIETER: pitch rises as sqrt(r), the same law as its wobble rate,
## and level falls as 1/r, the same law as its visible swing.
func rim_level_db() -> float:
	return -20.0 * log(rim_rigidity) / log(10.0)


func rim_pitch() -> float:
	return sqrt(rim_rigidity)


## A rim hit: the hoop's miss clip, rate-limited so a rattle plays it once.
## This IS the rim's sound now, so it carries the rigidity scaling.
func miss_on_rim() -> void:
	var now := Time.get_ticks_usec()
	if now - _last_miss_usec < int(MISS_RATE_LIMIT_S * 1_000_000.0):
		return
	_last_miss_usec = now
	_play_from(_hoop, "hoop", "miss", MISS_GAIN_DB + rim_level_db(), rim_pitch())


func miss() -> void:
	_play_from(_hoop, "hoop", "miss", MISS_GAIN_DB)


func pickup() -> void:
	_play_from(_ball, "ball", "pickup")


func release() -> void:
	_play_from(_ball, "ball", "release")


# ---- generic ----------------------------------------------------------------------


func swish() -> void:
	_play("swish")


func net_rustle() -> void:
	_play("chain_rattle_0" if _net_kind == "chain" else "net")


func score_pop(is_swish: bool) -> void:
	_play("score_pop_swish" if is_swish else "score_pop")


func buzzer() -> void:
	_play("buzzer")


## Hot streak: the rim catching fire (Fire Burst by SilverIllusionist, credited).
func fire_burst() -> void:
	_play("fx/fire_burst", -4.0)


## The fire going out (MatchstickDeath-03 by Wavewire, credited).
func fire_out() -> void:
	_play("fx/fire_out", -3.0)


## Cold streak: the rim icing over (Ice Cracking by timbreknight, trimmed,
## credited), a chip off it, and the break (still synthesized).
func ice_freeze() -> void:
	_play("fx/ice_form", -2.0)


func ice_crack() -> void:
	_play("ice_crack_%d" % _rng.randi_range(0, 1))


## The ice breaking: a swish through it gets the sharper glass break
## (mp glass break by cmusounddesign); a caught ball or three rim hits get the
## heavier crash (Breaking Glass Mix by theplax). Both credited.
func ice_shatter(swish := false) -> void:
	_play("fx/ice_swish" if swish else "fx/ice_break", -3.0)
