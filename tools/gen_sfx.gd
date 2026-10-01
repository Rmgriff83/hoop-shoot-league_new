extends SceneTree
## Offline SFX renderer: bakes the procedural Web Audio recipes from the
## original game (src/engine/sfx.ts) into WAV files. The game then plays plain
## AudioStreamPlayers — no audio-thread buffer feeding, and the "all sound is
## synthesized from a checked-in script" property is preserved.
## Run: godot --headless --path . -s tools/gen_sfx.gd
##
## Impact sounds bake 3 intensity variants (i = 0.33 / 0.66 / 1.0); runtime
## picks the variant and scales volume_db from the physics impact speed.
## Master gain 0.55 is baked in.

const SR := 44100
const MASTER := 0.55
const OUT_DIR := "res://assets/audio"

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var intensities := [0.33, 0.66, 1.0]
	for i in 3:
		_save("rim_clang_%d" % i, _rim_clang(intensities[i], i))
		_save("board_thud_%d" % i, _board_thud(intensities[i], i))
		_save("bounce_%d" % i, _bounce(intensities[i]))
	_save("swish", _swish())
	_save("net", _net())
	_save("score_pop", _score_pop(false))
	_save("score_pop_swish", _score_pop(true))
	_save("buzzer", _buzzer())
	_save("ice_freeze", _ice_freeze())
	for i in 2:
		_save("ice_crack_%d" % i, _ice_crack(i))
	_save("ice_shatter", _ice_shatter())
	for i in 3:
		_save("chain_swish_%d" % i, _chain_swish(i))
	for i in 2:
		_save("chain_rattle_%d" % i, _chain_rattle(i))
	# PEGGY, the locker's drop machine (docs/LOCKER.md).
	_save("peggy_press", _peggy_press())
	_save("peggy_servo", _peggy_servo())
	_save("peggy_ticket", _peggy_ticket())
	for i in 3:
		_save("peggy_peg_%d" % i, _peggy_peg(i))
	_save("peggy_win", _peggy_win())
	_save("match_loss", _match_loss())
	_save("peggy_jackpot", _peggy_jackpot())
	print("sfx done")
	quit(0)


# ---- recipe renders ----------------------------------------------------------


## Metallic rim clang — three detuned triangle partials + a bright noise tick.
func _rim_clang(intensity: float, variant: int) -> PackedFloat64Array:
	_rng.seed = 1000 + variant  # bake the ±2% detune deterministically per variant
	var amp := 0.25 + 0.6 * minf(intensity, 1.0)
	var decay := 0.16 + 0.12 * intensity
	var dur := 0.002 + decay + 0.05
	var buf := _silence(dur)
	for partial: Array in [[2350.0, 1.0], [3170.0, 0.55], [1420.0, 0.4]]:
		var freq: float = partial[0] * (0.98 + _rng.randf() * 0.04)
		var tone := _osc("triangle", freq, freq, 0.0, dur)
		_apply_env(tone, amp * partial[1] * 0.2, 0.002, decay)
		_mix(buf, tone, 0.0)
	var tick := _noise(0.06, 2000 + variant)
	tick = _biquad_bandpass(tick, 3000.0, 3000.0, 0.0, 2.0)
	_apply_env(tick, amp * 0.15, 0.001, 0.05)
	_mix(buf, tick, 0.0)
	return buf


## Ice forming — a rising crystalline shimmer: high sine partials sweeping up
## under a slow envelope, plus a whisper of bandpassed noise.
func _ice_freeze() -> PackedFloat64Array:
	_rng.seed = 4100
	var dur := 0.75
	var buf := _silence(dur)
	for partial: Array in [[1900.0, 3400.0, 0.5], [2800.0, 5200.0, 0.35], [4200.0, 7600.0, 0.22]]:
		var tone := _osc("sine", partial[0], partial[1], dur * 0.8, dur)
		_apply_env(tone, 0.12 * partial[2], 0.12, 0.45)
		_mix(buf, tone, 0.0)
	var air := _noise(dur, 4101)
	air = _biquad_bandpass(air, 5000.0, 9000.0, dur, 4.0)
	_apply_env(air, 0.05, 0.2, 0.4)
	_mix(buf, air, 0.0)
	return buf


## Ice cracking — the rim clang recipe pitched up and cut short: bright
## detuned partials with a fast decay and a sharp noise tick.
func _ice_crack(variant: int) -> PackedFloat64Array:
	_rng.seed = 4200 + variant
	var decay := 0.07 + 0.03 * variant
	var dur := decay + 0.04
	var buf := _silence(dur)
	for partial: Array in [[5200.0, 1.0], [7300.0, 0.5], [3900.0, 0.35]]:
		var freq: float = partial[0] * (0.97 + _rng.randf() * 0.06)
		var tone := _osc("triangle", freq, freq * 0.92, dur, dur)
		_apply_env(tone, 0.16 * partial[1], 0.001, decay)
		_mix(buf, tone, 0.0)
	var tick := _noise(0.04, 4300 + variant)
	tick = _biquad_bandpass(tick, 6500.0, 6500.0, 0.0, 1.5)
	_apply_env(tick, 0.2, 0.0005, 0.03)
	_mix(buf, tick, 0.0)
	return buf


## Ice shattering — a crack, then a glassy noise tail with a few falling
## partials (shards tinkling).
func _ice_shatter() -> PackedFloat64Array:
	_rng.seed = 4400
	var dur := 0.85
	var buf := _silence(dur)
	_mix(buf, _ice_crack(0), 0.0)
	var burst := _noise(0.5, 4401)
	burst = _biquad_bandpass(burst, 7000.0, 3500.0, 0.5, 1.2)
	_apply_env(burst, 0.22, 0.002, 0.4)
	_mix(buf, burst, 0.01)
	for i in 6:
		var f := 3000.0 + _rng.randf() * 4500.0
		var tink := _osc("sine", f, f * 0.9, 0.12, 0.14)
		_apply_env(tink, 0.06, 0.001, 0.1)
		_mix(buf, tink, 0.08 + i * 0.09 + _rng.randf() * 0.04)
	return buf


## Backboard thud — low knock (220→90 Hz) + woody lowpassed noise.
func _board_thud(intensity: float, variant: int) -> PackedFloat64Array:
	var amp := 0.3 + 0.55 * minf(intensity, 1.0)
	var buf := _silence(0.25)
	var tone := _osc("sine", 220.0, 90.0, 0.09, 0.25)
	_apply_env(tone, amp * 0.5, 0.002, 0.12)
	_mix(buf, tone, 0.0)
	var knock := _noise(0.05, 3000 + variant)
	knock = _biquad_lowpass(knock, 900.0, 0.707)
	_apply_env(knock, amp * 0.25, 0.001, 0.06)
	_mix(buf, knock, 0.0)
	return buf


## Floor bounce — classic hollow thump (140→55 Hz).
func _bounce(intensity: float) -> PackedFloat64Array:
	var amp := 0.2 + 0.5 * minf(intensity, 1.0)
	var tone := _osc("sine", 140.0, 55.0, 0.12, 0.3)
	_apply_env(tone, amp * 0.6, 0.003, 0.16)
	return tone


## Swish — soft filtered-noise whoosh with a falling sweep 2600→700 Hz.
func _swish() -> PackedFloat64Array:
	var n := _noise(0.35, 4001)
	n = _biquad_bandpass(n, 2600.0, 700.0, 0.28, 1.2)
	_apply_env(n, 0.5, 0.02, 0.3)
	return n


## Chain net make (the city court) — a metallic clatter: a short bright noise
## burst, five detuned metallic partials with fast decays, then a thinning
## tail of link ticks. Three seeded variants.
func _chain_swish(variant: int) -> PackedFloat64Array:
	_rng.seed = 5000 + variant
	var buf := _silence(0.6)
	var burst := _noise(0.12, 5100 + variant)
	burst = _biquad_bandpass(burst, 2600.0, 1400.0, 0.10, 1.0)
	_apply_env(burst, 0.35, 0.004, 0.09)
	_mix(buf, burst, 0.0)
	for partial: Array in [[1850.0, 0.9], [2450.0, 0.7], [3100.0, 0.55], [3700.0, 0.4], [4200.0, 0.3]]:
		var f: float = float(partial[0]) * (0.97 + _rng.randf() * 0.06)
		var tone := _osc("triangle", f, f * 0.97, 0.15, 0.25)
		_apply_env(tone, 0.14 * float(partial[1]), 0.002, 0.10 + _rng.randf() * 0.05)
		_mix(buf, tone, _rng.randf() * 0.03)
	for i in 10:
		var f := 2200.0 + _rng.randf() * 2600.0
		var tick := _osc("triangle", f, f * 0.95, 0.03, 0.035)
		_apply_env(tick, 0.05 * (1.0 - i / 12.0), 0.001, 0.025)
		_mix(buf, tick, 0.06 + i * 0.035 + _rng.randf() * 0.02)
	return buf


## Chain rattle — the links jangling on a rim hit: a handful of ticks and a
## short 2.6 kHz noise, quiet (it rides under the recorded rim clip).
func _chain_rattle(variant: int) -> PackedFloat64Array:
	_rng.seed = 5300 + variant
	var buf := _silence(0.3)
	var n := _noise(0.05, 5400 + variant)
	n = _biquad_bandpass(n, 2600.0, 1600.0, 0.05, 1.2)
	_apply_env(n, 0.12, 0.002, 0.04)
	_mix(buf, n, 0.0)
	for i in 6:
		var f := 2400.0 + _rng.randf() * 2200.0
		var tick := _osc("triangle", f, f * 0.95, 0.03, 0.035)
		_apply_env(tick, 0.04, 0.001, 0.025)
		_mix(buf, tick, 0.02 + i * 0.04 + _rng.randf() * 0.02)
	return buf


## Net rustle for non-swish makes — quieter, shorter than the full swish.
func _net() -> PackedFloat64Array:
	var n := _noise(0.18, 4002)
	n = _biquad_bandpass(n, 1800.0, 600.0, 0.15, 1.5)
	_apply_env(n, 0.28, 0.01, 0.16)
	return n


## Cheerful two-note square pop (higher pair for swishes), 70 ms stagger.
func _score_pop(swish: bool) -> PackedFloat64Array:
	var notes := [880.0, 1318.5] if swish else [659.25, 880.0]
	var buf := _silence(0.07 + 0.2)
	for i in 2:
		var tone := _osc("square", notes[i], notes[i], 0.0, 0.2)
		_apply_env(tone, 0.12, 0.005, 0.14)
		_mix(buf, tone, i * 0.07)
	return buf


## Buzzer — two detuned sawtooths at 210/213 Hz.
func _buzzer() -> PackedFloat64Array:
	var buf := _silence(0.55)
	for freq in [210.0, 213.0]:
		var tone := _osc("sawtooth", freq, freq, 0.0, 0.55)
		_apply_env(tone, 0.3, 0.01, 0.5)
		_mix(buf, tone, 0.0)
	return buf


# ---- PEGGY ---------------------------------------------------------------------


## The big red button going in: a chunky low thud under a short click.
func _peggy_press() -> PackedFloat64Array:
	var buf := _silence(0.22)
	var thud := _osc("sine", 90.0, 55.0, 0.12, 0.18)
	_apply_env(thud, 0.85, 0.004, 0.14)
	var click := _biquad_bandpass(_noise(0.03, 7701), 2600.0, 1800.0, 0.03, 2.0)
	_apply_env(click, 0.5, 0.001, 0.02)
	var body := _biquad_lowpass(_noise(0.08, 7702), 400.0, 0.7)
	_apply_env(body, 0.25, 0.002, 0.06)
	_mix(buf, click, 0.0)
	_mix(buf, thud, 0.004)
	_mix(buf, body, 0.004)
	return buf


## The carriage's servo: a 0.4 s FLAT loop (no envelope) — a low saw with a
## 9 Hz wobble, a faint whistle and a noise bed, 5 ms end fades for a clean
## loop point. Sfx loops it while the finger moves the aim.
func _peggy_servo() -> PackedFloat64Array:
	var dur := 0.4
	var saw := _osc("sawtooth", 140.0, 140.0, 0.0, dur)
	for i in saw.size():
		saw[i] *= 0.85 + 0.15 * sin(TAU * 9.0 * float(i) / SR)
	saw = _biquad_lowpass(saw, 1400.0, 0.9)
	var whistle := _osc("sine", 2200.0, 2240.0, dur, dur)
	var bed := _biquad_bandpass(_noise(dur, 7703), 900.0, 900.0, 0.0, 1.0)
	var buf := _silence(dur)
	for i in buf.size():
		buf[i] = saw[i] * 0.22 + whistle[i] * 0.06 + bed[i] * 0.08
	var fade := int(0.005 * SR)
	for i in fade:
		var g := float(i) / float(fade)
		buf[i] *= g
		buf[buf.size() - 1 - i] *= g
	return buf


## A ticket sliding into the slot: a falling noise swish, then the stub seats.
func _peggy_ticket() -> PackedFloat64Array:
	var buf := _silence(0.55)
	var sw := _biquad_bandpass(_noise(0.5, 7704), 1400.0, 500.0, 0.45, 0.8)
	_apply_env(sw, 0.5, 0.05, 0.4)
	var tick := _biquad_bandpass(_noise(0.02, 7705), 3200.0, 3200.0, 0.0, 3.0)
	_apply_env(tick, 0.3, 0.001, 0.015)
	_mix(buf, sw, 0.0)
	_mix(buf, tick, 0.42)
	return buf


## A peg hit: a 40 ms bright tick (three pitches) with a tiny click.
func _peggy_peg(variant: int) -> PackedFloat64Array:
	var f: float = [1800.0, 2200.0, 2600.0][variant % 3]
	var buf := _silence(0.06)
	var tone := _osc("triangle", f, f * 0.9, 0.04, 0.05)
	_apply_env(tone, 0.6, 0.001, 0.035)
	var click := _biquad_bandpass(_noise(0.004, 7710 + variant), 4000.0, 4000.0, 0.0, 2.0)
	_apply_env(click, 0.3, 0.0005, 0.003)
	_mix(buf, tone, 0.0)
	_mix(buf, click, 0.0)
	return buf


## A league heat lost (the match-end page): two falling square notes and a
## low thud under the second.
func _match_loss() -> PackedFloat64Array:
	var buf := _silence(0.9)
	var a := _osc("square", 392.0, 392.0, 0.0, 0.22)
	_apply_env(a, 0.2, 0.005, 0.2)
	_mix(buf, a, 0.0)
	var b := _osc("square", 261.6, 246.9, 0.3, 0.5)
	_apply_env(b, 0.22, 0.005, 0.45)
	_mix(buf, b, 0.26)
	var thud := _osc("sine", 70.0, 48.0, 0.3, 0.4)
	_apply_env(thud, 0.5, 0.004, 0.35)
	_mix(buf, thud, 0.26)
	return buf


## A ball won: a rising three-note square arpeggio with a sine tail.
func _peggy_win() -> PackedFloat64Array:
	var buf := _silence(0.7)
	var notes := [659.25, 783.99, 1046.5]
	for i in 3:
		var tone := _osc("square", notes[i], notes[i], 0.0, 0.12)
		_apply_env(tone, 0.25, 0.005, 0.11)
		_mix(buf, tone, i * 0.10)
	var tail := _osc("sine", 1046.5, 1046.5, 0.0, 0.35)
	_apply_env(tail, 0.2, 0.01, 0.3)
	_mix(buf, tail, 0.30)
	return buf


## An epic or legend pull: a six-note run, a detuned saw chord and a sparkle.
func _peggy_jackpot() -> PackedFloat64Array:
	var buf := _silence(1.6)
	var run := [523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0]
	for i in run.size():
		var tone := _osc("square", run[i], run[i], 0.0, 0.11)
		_apply_env(tone, 0.22, 0.004, 0.1)
		_mix(buf, tone, i * 0.09)
	for detune in [1.0, 1.004]:
		for f in [1046.5, 1318.5, 1568.0]:
			var tone := _osc("sawtooth", f * detune, f * detune, 0.0, 0.65)
			_apply_env(tone, 0.14 if detune == 1.0 else 0.08, 0.02, 0.55)
			_mix(buf, tone, 0.55 if detune == 1.0 else 0.57)
	var sparkle := _biquad_bandpass(_noise(0.5, 7720), 6000.0, 7000.0, 0.5, 3.0)
	_apply_env(sparkle, 0.15, 0.05, 0.45)
	_mix(buf, sparkle, 0.6)
	return buf


# ---- DSP helpers -------------------------------------------------------------


func _silence(seconds: float) -> PackedFloat64Array:
	var buf := PackedFloat64Array()
	buf.resize(ceili(seconds * SR))
	return buf


## Oscillator with optional exponential frequency sweep f0→f1 over sweep_t.
func _osc(shape: String, f0: float, f1: float, sweep_t: float, dur: float) -> PackedFloat64Array:
	var buf := _silence(dur)
	var phase := 0.0
	var ratio := 1.0 if f0 == f1 else f1 / f0
	for i in buf.size():
		var t := float(i) / SR
		var f := f0
		if sweep_t > 0.0:
			f = f1 if t >= sweep_t else f0 * pow(ratio, t / sweep_t)
		phase += f / SR
		var frac := phase - floorf(phase)
		match shape:
			"sine":
				buf[i] = sin(TAU * phase)
			"triangle":
				buf[i] = 4.0 * absf(frac - 0.5) - 1.0
			"square":
				buf[i] = 1.0 if frac < 0.5 else -1.0
			"sawtooth":
				buf[i] = 2.0 * frac - 1.0
	return buf


func _noise(seconds: float, seed_v: int) -> PackedFloat64Array:
	_rng.seed = seed_v
	var buf := _silence(seconds)
	for i in buf.size():
		buf[i] = _rng.randf() * 2.0 - 1.0
	return buf


## envGain port: exponential ramp 0.0001→peak over attack, →0.0001 over decay.
func _apply_env(buf: PackedFloat64Array, peak: float, attack: float, decay: float) -> void:
	peak = maxf(peak, 0.0001)
	for i in buf.size():
		var t := float(i) / SR
		var g := 0.0
		if t < attack:
			g = 0.0001 * pow(peak / 0.0001, t / attack)
		elif t < attack + decay:
			g = peak * pow(0.0001 / peak, (t - attack) / decay)
		buf[i] *= g


## RBJ bandpass (constant 0 dB peak gain), with optional exponential center sweep.
func _biquad_bandpass(src: PackedFloat64Array, f0: float, f1: float, sweep_t: float, q: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(src.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var ratio := 1.0 if f0 == f1 else f1 / f0
	for i in src.size():
		var t := float(i) / SR
		var f := f0
		if sweep_t > 0.0:
			f = f1 if t >= sweep_t else f0 * pow(ratio, t / sweep_t)
		var w := TAU * f / SR
		var alpha := sin(w) / (2.0 * q)
		var cw := cos(w)
		var b0 := alpha
		var b2 := -alpha
		var a0 := 1.0 + alpha
		var a1 := -2.0 * cw
		var a2 := 1.0 - alpha
		var x0 := src[i]
		var y0 := (b0 * x0 + b2 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1
		x1 = x0
		y2 = y1
		y1 = y0
		out[i] = y0
	return out


func _biquad_lowpass(src: PackedFloat64Array, freq: float, q: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(src.size())
	var w := TAU * freq / SR
	var alpha := sin(w) / (2.0 * q)
	var cw := cos(w)
	var b0 := (1.0 - cw) / 2.0
	var b1 := 1.0 - cw
	var b2 := (1.0 - cw) / 2.0
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cw
	var a2 := 1.0 - alpha
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in src.size():
		var x0 := src[i]
		var y0 := (b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1
		x1 = x0
		y2 = y1
		y1 = y0
		out[i] = y0
	return out


func _mix(dst: PackedFloat64Array, src: PackedFloat64Array, at_seconds: float) -> void:
	var offset := roundi(at_seconds * SR)
	var needed := offset + src.size()
	if needed > dst.size():
		dst.resize(needed)
	for i in src.size():
		dst[offset + i] += src[i]


func _save(name: String, buf: PackedFloat64Array) -> void:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		var v := clampf(buf[i] * MASTER, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(v * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	wav.data = bytes
	var path := "%s/%s.wav" % [OUT_DIR, name]
	var err := wav.save_to_wav(path)
	print("wrote %s (%s)" % [path, "ok" if err == OK else str(err)])
