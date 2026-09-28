class_name CardEffects
extends RefCounted
## The effect registry: `apply(kind, params, heat, target)` acts on one side of
## a Heat. Returns true when the effect took (a card is only consumed then).

const KINDS := ["ice", "fire", "vortex"]


static func apply(kind: String, params: Dictionary, heat: Heat, target: String) -> bool:
	var side := heat.side(target)
	match kind:
		"ice":
			# Same rules as the cold streak: the target must swish through it,
			# get caught and popped, or rattle the rim three times.
			return side.freeze_rim("card")
		"fire":
			# The target's own rim burns for `seconds`: makes pay like a hot
			# streak from FIRE_AT; a miss or the clock puts it out.
			return side.light_rim(float(params.get("seconds", 0.0)), "card")
		"vortex":
			# The target's own rim pulls for `seconds`: any ball that touches
			# iron or board is dragged through. Only the clock (or ice) ends it.
			return side.spin_rim(float(params.get("seconds", 0.0)), "card")
		_:
			return false


## Can the effect apply right now? (Keeps the tray honest: a greyed card.)
static func can_apply(kind: String, heat: Heat, target: String) -> bool:
	match kind:
		"ice":
			return not heat.side(target).iced and heat.side(target).phase == TimeTrial.PHASE_RUNNING
		"fire":
			var side := heat.side(target)
			return side.phase == TimeTrial.PHASE_RUNNING and not side.iced and not side.fire_card and not StreakRules.is_lit(side.streak)
		"vortex":
			var side := heat.side(target)
			return side.phase == TimeTrial.PHASE_RUNNING and not side.iced and not side.vortex_card
		_:
			return false
