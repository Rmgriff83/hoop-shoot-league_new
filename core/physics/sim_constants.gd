class_name SimConstants
extends RefCounted
## All physics in real-world meters (handoff §3 — validated numbers, do not tweak
## the first block). The second block is the game-feel tuning surface.
## Ported line-faithfully from hoop_shoot_league src/core/physics/constants.ts.

# ---- Validated spec numbers (handoff §3) ----
const G := 9.81
const RIM_HEIGHT := 3.05
const RELEASE_HEIGHT := 2.1
const SHOT_DIST := 7.24

# ---- Regulation geometry ----
const R_RIM := 0.2286
const R_TUBE := 0.016
const R_BALL := 0.121
const BOARD_OFFSET := 0.3796
const BOARD_BOTTOM := 2.9
const BOARD_TOP := 3.95
const BOARD_HALF_W := 0.915

# Canonical shot space: release at (0, RELEASE_HEIGHT, 0), ball travels +x.
# (The default when a launch carries no rx/ry/rz release origin — see ShotSim.)
const HOOP_X := SHOT_DIST
const HOOP_Y := RIM_HEIGHT
const BOARD_X := HOOP_X + BOARD_OFFSET

# Rim mounting bracket: fills the shelf between the back rim tube and the board
# face — otherwise a square back-rim miss can wedge there and rest. Modeled as a
# steeply sloped ribbon rising rim→board; anything landing on it slides forward
# onto the back rim and resolves naturally.
const BRACKET_X0 := HOOP_X + R_RIM - 0.01
const BRACKET_X1 := BOARD_X
const BRACKET_Y0 := RIM_HEIGHT
const BRACKET_Y1 := RIM_HEIGHT + 0.15
const BRACKET_HALF_W := 0.2

# ---- Simulation ----
const SIM_DT := 1.0 / 240.0
const MAX_SHOT_TIME := 7.0
## How long a ball may rest off the floor before it is declared dead. Long
## enough that a ball balanced on the ring topples off on its own (measured:
## ~0.85 s) instead of vanishing in mid-air; MAX_SHOT_TIME is the hard backstop.
const DEAD_BALL_S := 1.5
const BACKSPIN_DEFAULT := 15.0

# ---- Materials / game feel (tuning surface — sandbox-validated) ----
const E_RIM := 0.32
const MU_RIM := 0.12
const SPIN_KICK := 0.25
const SPIN_DECAY_RIM := 0.55
const E_BOARD := 0.68
const MU_BOARD := 0.2
const SPIN_DECAY_BOARD := 0.7
const E_FLOOR := 0.62
const MU_FLOOR := 0.15
## How much of the ball's slip against the FLOOR is converted into rotation on
## each bounce. Friction at the contact patch is a torque, not just a drag on
## the path: a ball that lands with backspin grips and is driven toward rolling.
## 0 = the old behaviour (spin merely decayed and the ball kept spinning the way
## it was thrown); 1 = it reaches true rolling in a single bounce.
const FLOOR_SPIN_GRIP := 0.6
const NET_DRAG := 2.6
const E_NET_WALL := 0.08

# Make/dead-ball thresholds
const MAKE_DEPTH := 0.22
const NET_EXIT_Y := RIM_HEIGHT - 0.6
