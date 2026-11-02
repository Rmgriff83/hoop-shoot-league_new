# Game Center plugin — godot-ios-plugins (Godot Engine contributors)

- **Source:** https://github.com/godotengine/godot-ios-plugins, `plugins/gamecenter`
  at commit `caafb2c7fbfb5c72a64f163c76449274fa49abaa` (master, pulled 2026-11-01).
- **Licence:** MIT (`LICENCE`, the repo's own file, copied here).
- **Why vendored:** the repo publishes binaries for Godot 3.x only; a 4.x
  plugin must be built against the engine's own headers, which
  `tools/build_gamecenter_plugin.sh` does (docs/BUILD.md → The Game Center
  plugin). The built xcframeworks live outside the repo like the other
  plugins' binaries.
- **What we changed** (`game_center.mm`, `gamecenter.gdip`; grep `hoop_shoot`):
  - GameKit is imported before Godot's headers (GameController's `Key`
    clashes with Godot's `enum class Key` once both are visible).
  - The root view controller comes through the connected `UIWindowScene`'s
    key window when there is one (`godot_gc_root_controller`), else the
    delegate's window as before.
  - The identity-signature event is handed to the main queue before it is
    queued, since GameKit may answer off the main thread.
  - `capabilities=["gamekit"]` dropped from the .gdip (no
    `UIRequiredDeviceCapabilities` constraint); GameKit still links through
    `system=["GameKit.framework"]`.
  - The `award_achievement` event carries `name` (the achievement id it
    answers for), 2026-11-02.
- **Used by:** `game/net/game_center_backend.gd` (`authenticate`,
  `is_authenticated`, `request_identity_verification_signature`,
  `get_pending_event_count`, `pop_pending_event`; since 2026-11-02
  `award_achievement`, `request_achievements`, `show_game_center` —
  docs/ACHIEVEMENTS.md). Scores are compiled in but unused.
