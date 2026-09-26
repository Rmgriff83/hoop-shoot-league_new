# Area interactables

Tappable props that are unique to an area. Presentation only — nothing here touches the sim.

- **Data**: `ArenaSet.interactables` (the area's `arena_set.tres`), one row per prop:
  `{"kind": "radio", "node": "Boombox", "pad": 0.08, ...params}`. `node` is the glb node name
  (`find_child`), `pad` grows the tap box in metres; the rest is the kind's own parameters.
  Any `tracks` paths are validated with the set (`referenced_paths`).
- **Kinds**: `game/court/interactable_kinds.gd` maps `kind` → a script extending
  `game/court/interactable.gd` (`Interactable`). Override `_after_setup`, `on_tap(court)`,
  `on_leave()`. Picking is a camera ray against the target's local mesh bounds
  (`hit(origin, dir)`), no physics, so it runs headless.
- **Wiring**: `CourtGeometry._build_interactables` builds them under an `Interactables` node
  after the arena model loads; `pick_interactable(cam, pos)` returns the nearest hit;
  `leave_interactables()` runs from the screen's `_exit_tree`. `time_trial_screen._input`
  consumes a press (and its release) that lands on a prop so the flick input never grabs.
- **Hints**: `game/view/prop_icons.gd` (`PropIcons`, CanvasLayer 6) projects each prop's
  `anchor()` and draws its `icons()` — small discs: "tap" (music note, breathing) when idle,
  "next" + a smaller red "off" while the radio plays. The screen checks `hit_icon(pos)` before
  the ray pick and calls `on_icon(id, court)`.
- **Radio** (`game/court/interactables/radio.gd`): params `tracks`, `gain_db`, optional `seed`.
  Tap cycle: off → track 0 (the title loop) → the rest in a random order drawn per lap → off.
  Feedback is minimal: the hint discs above the boombox, the `BoomboxLed` glow, and a 0.15 s
  nudge on the tap.
  Audio rides `Sfx.play_track / stop_track / track_id` — its own looping player beside the
  area's ambience layers; `stop_ambience` (leaving the area) clears it too. Tracks are encoded
  with `tools/import_music.sh` and credited in `data/credits.json`.

Add a prop: name the node in the Blender build script, write a kind script, add the row.
