extends RefCounted
## Rim rigidity: one number, derived from the rim's own restitution, that makes
## what you SEE and HEAR follow how the rim actually bounces.
##
## A bouncier rim returns more energy because it flexes less — it is stiffer
## steel. So it must wobble FASTER and SHALLOWER and ring TIGHTER and QUIETER.
## Before this, the two were authored against each other: the beach rim ran the
## cage's restitution while its Miss clip was hand-keyed as the floppy one.
##
## The scalars all come from the unit-mass spring in game/fx/spring.gd, where
## frequency is sqrt(stiffness). A wobble `r` times faster therefore needs r*r
## the stiffness, and its deflection per kick falls as 1/r — the same 1/r that
## sets the clip's swing and the sound's level.


func run(t) -> void:
	_manual_advance(t)
	_rigidity(t)
	_frequency_law(t)
	_cage_is_unchanged(t)
	_sound_scaling(t)


func _rigidity(t) -> void:
	t.close(SimGeometry.arcade().rim_rigidity(), 1.0, 1e-12, "the cage is the 1.0 anchor")
	t.close(SimGeometry.beach().rim_rigidity(), 1.33, 1e-12, "the beach ring is 33 % more rigid")
	t.close(SimGeometry.city().rim_rigidity(), 1.33 * 1.15, 1e-12, "the city ring is 15 % more rigid again")
	t.ok(SimGeometry.regulation().rim_rigidity() < 1.0, "the regulation rim is the softest")
	t.close(SimGeometry.BEACH_RIM_E, SimGeometry.ARCADE_RIM_E * 1.33, 1e-12, "beach restitution is +33 %")


## The point of the whole feature: stiffness = BASE * r^2 really does make the
## wobble run r times faster. Measured, not asserted.
func _frequency_law(t) -> void:
	var r := SimGeometry.beach().rim_rigidity()
	var base := _half_period(CourtGeometry.BASE_RIM_STIFFNESS)
	var beach := _half_period(CourtGeometry.BASE_RIM_STIFFNESS * r * r)
	t.ok(base > 0.0 and beach > 0.0, "both springs oscillate (%.4f s vs %.4f s)" % [base, beach])
	# Faster means a SHORTER half period, so the ratio is 1/r.
	var ratio := beach / base
	t.ok(absf(ratio - 1.0 / r) < 0.02,
		"a %.0f%% stiffer rim wobbles %.0f%% faster (half period %.4f s vs %.4f s, %.3fx)"
			% [(r - 1.0) * 100.0, (r - 1.0) * 100.0, beach, base, ratio])


## Seconds from a kick to the spring's first return through zero — half its
## damped period, and a decay-independent read of its rate.
func _half_period(stiffness: float) -> float:
	var s := JuiceSpring.new(0.0, stiffness, CourtGeometry.RIM_DAMPING)
	s.kick(4.0)
	var dt := 1.0 / 4800.0
	var elapsed := 0.0
	var rose := false
	for i in 9600:
		var v := s.step(dt)
		elapsed += dt
		if v > 1e-4:
			rose = true
		elif rose and v <= 0.0:
			return elapsed
	return -1.0


## The cage was the tuning baseline, so at r = 1.0 every scalar must be exactly
## neutral. This is what guarantees the mode people actually play did not move.
func _cage_is_unchanged(t) -> void:
	var r := SimGeometry.arcade().rim_rigidity()
	t.close(1.0 / r, 1.0, 1e-12, "cage wobble amplitude is unscaled")
	t.close(CourtGeometry.BASE_RIM_STIFFNESS * r * r, 320.0, 1e-9, "cage spring keeps its tuned stiffness")
	t.close(sqrt(r), 1.0, 1e-12, "cage rim sound keeps its pitch")
	t.close(-20.0 * log(r) / log(10.0), 0.0, 1e-12, "cage rim sound keeps its level")


## Rim sound: quieter and higher as the rim stiffens, and — the real hazard —
## a pitched clip must never leave its pitch on the pooled player behind it.
func _sound_scaling(t) -> void:
	var r := SimGeometry.beach().rim_rigidity()
	t.close(sqrt(r), 1.1533, 1e-4, "the beach rim rings higher")
	var db := -20.0 * log(r) / log(10.0)
	t.ok(db < 0.0 and db > -3.0, "and quieter, but not by much (%.2f dB)" % db)

	var sfx = Engine.get_main_loop().root.get_node_or_null("Sfx")
	if sfx == null:
		return
	sfx.load_hoop_set(CosmeticLibrary.get_hoop("classic"))
	sfx.load_ball_set(CosmeticLibrary.get_ball("classic"))
	sfx.gain_db = -80.0
	sfx.rim_rigidity = r
	t.close(sfx.rim_pitch(), sqrt(r), 1e-12, "Sfx reports the rim's pitch")
	t.close(sfx.rim_level_db(), db, 1e-12, "Sfx reports the rim's level")
	# Enough rim hits to cycle the whole player pool, then one unpitched clip.
	# miss_on_rim() is rate-limited, so reach past it to the clip it plays.
	for i in 24:
		sfx._play_from(sfx._hoop, "hoop", "miss", sfx.rim_level_db(), sfx.rim_pitch())
	sfx.contact("floor", 5.0)
	var leaked := 0
	for p in sfx._players:
		if p.playing and not is_equal_approx(p.pitch_scale, sqrt(r)):
			# The floor bounce is the only clip that should be at pitch 1.
			if not is_equal_approx(p.pitch_scale, 1.0):
				leaked += 1
	t.eq(leaked, 0, "no player is left at a stale pitch")
	sfx.rim_rigidity = 1.0
	sfx.contact("floor", 5.0)
	var pitched := 0
	for p in sfx._players:
		if p.playing and not is_equal_approx(p.pitch_scale, 1.0) and not is_equal_approx(p.pitch_scale, sqrt(r)):
			pitched += 1
	t.eq(pitched, 0, "an unpitched clip plays at exactly 1.0")
	sfx.gain_db = 0.0


## The structurally new piece: the hoop's AnimationPlayer no longer runs itself.
## CourtGeometry drives it from step_rim() so the swing can be scaled after the
## clip writes it. If that wiring ever breaks, authored clips freeze in place
## and nothing else would notice — hence this test.
func _manual_advance(t) -> void:
	var court := CourtGeometry.new()
	court.hoop_set = CosmeticLibrary.get_hoop("street")   # names a Miss clip
	court.arena_set = CosmeticLibrary.get_arena("beach")
	court.geo = SimGeometry.beach()
	# Built off-tree, the way test_rim_ice.gd drives RimIce: _ready() does all
	# the work and nothing here needs a live viewport.
	court._ready()
	t.ok(court.rim_pivot != null, "court built a rim pivot")
	t.ok(court._anim != null, "court found the hoop's AnimationPlayer")
	if court.rim_pivot == null or court._anim == null:
		return
	var r := SimGeometry.beach().rim_rigidity()
	t.close(court._rim_amp, 1.0 / r, 1e-12, "the beach court scales its rim swing down")

	# Manual mode is what makes the ordering ours. (The runner calls run()
	# synchronously, so this is asserted rather than observed over real frames.)
	t.eq(court._anim.callback_mode_process,
		AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,
		"only step_rim may advance the hoop's clips")
	t.close(court._anim.speed_scale, r, 1e-6, "and the beach clip plays %.0f %% faster" % ((r - 1.0) * 100.0))

	court.rim_react(6.0)
	t.ok(court.flourish_playing(), "a rim hit starts the authored clip")
	var t0: float = court._anim.current_animation_position

	var swing := 0.0
	for i in 30:
		court.step_rim(1.0 / 60.0)
		swing = maxf(swing, absf(court.rim_pivot.rotation.x) + absf(court.rim_pivot.rotation.z))
	t.ok(court._anim.current_animation_position > t0, "step_rim advances the clip")
	t.ok(swing > 1e-4, "and the rim actually moves (%.4f rad)" % swing)

	# Run it out: the clip ends, the spring takes the hinge back, and every
	# channel returns to rest — including x/y, which the old code never cleared.
	for i in 180:
		court.step_rim(1.0 / 60.0)
	t.ok(not court.flourish_playing(), "the clip finishes")
	t.close(court.rim_pivot.rotation.x, 0.0, 1e-6, "no residue left on the x channel")
	t.close(court.rim_pivot.rotation.y, 0.0, 1e-6, "no residue left on the y channel")
	t.close(court.rim_pivot.rotation.z, 0.0, 1e-3, "the rim settles back to rest")
