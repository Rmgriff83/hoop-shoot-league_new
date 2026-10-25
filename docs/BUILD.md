# Building for the stores

The app is **Hoop Shoot League** (Ross, 2026-10-24): `application/config/name`
is the iOS display name and the Android presets' `package/name` the launcher
label; the ids stay `com.rossgriffus.hoopshoot`, and the Mac's `user://` folder
keeps the old name through `config/custom_user_dir_name` so saves and QA snaps
stay where they are.

One command, both platforms (set up 2026-10-24, modelled on the bball sim's
`npm run release` — no web build here):

| Command | What comes out |
|---|---|
| `tools/build.sh` | the Play AAB (release) **and** the iOS Xcode project |
| `tools/build.sh android` | `build/hoop_shoot.aab` (release, gradle, the upload keystore) |
| `tools/build.sh android --debug` | `build/hoop_shoot.apk` (the fast phone build, no gradle) |
| `tools/build.sh --deploy` | the debug APK, installed and launched on the phone |
| `tools/build.sh ios` | `build/ios/hoop_shoot.xcodeproj` + `hoop_shoot.pck` |
| `tools/build.sh ios --open` | …and opens it in Xcode |

`tools/android_deploy.sh` still works on its own (`--no-export` reinstalls
the APK); `tools/build.sh --deploy` is the same loop through the one command.

Rules the script enforces: the editor must be closed (one Godot at a time);
a release build refuses a dirty tree (commit or stash first — the
`export_presets.cfg` version lines are exempt, see Versioning); the Play
build needs the keystore setup below.

## Versioning

- The **version** (`1.0.0`) is `application/config/version` in
  `project.godot`. Bump it by hand for a store release. Android's version
  name and iOS's short version both fall back to it (empty in the presets).
- The **build number** is the git commit count (`git rev-list --count HEAD`).
  The script writes it into `export_presets.cfg` — `version/code` on both
  Android presets, `application/version` on iOS — before exporting. That is
  the only thing the script changes in the repo; commit the diff with the
  release. It rises on its own, so never rewrite `main`'s history.
- `NetConfig.version()` reports the project version on the wire.

## One-time setup

### Android: the upload keystore (outside the repo)

```
mkdir -p ~/.config/hoop_shoot
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
"$JAVA_HOME/bin/keytool" -genkeypair -v -keystore ~/.config/hoop_shoot/upload.jks \
  -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

Then `~/.config/hoop_shoot/release.env` (`chmod 600`):

```
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$HOME/.config/hoop_shoot/upload.jks"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="upload"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="…"
```

Godot reads those three variables when the preset's `keystore/release*`
fields are empty (they are, and stay so — no secret ever enters the repo).
**Back the `.jks` up** somewhere safe: with Play App Signing the upload key
can be reset through Google, without it a lost key means a new listing.

The first Play build installs Godot's gradle template into `android/`
(git-ignored; `android/.build_version` pins it to the editor version) and
downloads gradle's dependencies — expect several minutes once, under a
minute after. After a Godot upgrade the script reinstalls the template on
its own; if gradle misbehaves, `rm -rf android` and rerun.

The Play Console account does not exist yet (2026-10-24). When it does:
Play Console → the app → Testing → Internal testing → create a release →
upload `build/hoop_shoot.aab`. The package is `com.rossgriffus.hoopshoot`.

### iOS: Xcode signs, Ross archives

The preset carries the team (`U8XP33P732`) and the bundle id
(`com.rossgriffus.hoopshoot`, the Android package), with automatic signing
(no identities or profiles in the preset; Xcode manages them from the
signed-in Apple account). The export writes the Xcode project only
(`application/export_project_only`), because Ross archives and uploads by
hand:

1. `tools/build.sh ios --open`.
2. In Xcode pick **Any iOS Device (arm64)** as the destination. Under
   Signing & Capabilities the team should read Ross's and show "Automatically
   manage signing"; Xcode creates the distribution certificate and profile
   on first use (sign in under Xcode → Settings → Accounts if asked).
3. **Product → Archive**, then in the Organizer **Distribute App → App Store
   Connect → Upload**. The first upload needs an app record for the bundle id
   in App Store Connect (create it there first, iOS, the same bundle id).
4. TestFlight picks the build up after processing (10–30 min).

Every export rewrites `build/ios/` (`delete_old_export_files_unconditionally`),
so nothing done inside that Xcode project survives — change the preset or
the game, not the generated project. The icon set is resized from
`assets/icon/icon_1024.png` with nearest-neighbour (pixel art).

## The icon

`assets/icon/` holds a placeholder: the game's 22 px pixel ball on the ink,
rendered by `tools/render_icon.gd`
(`godot --headless --path . -s tools/render_icon.gd && godot --headless --path . --import`)
as `icon_1024.png` (iOS + `application/config/icon`), `android_192.png`
and the adaptive `adaptive_fg_432.png` / `adaptive_bg_432.png`. When the
real icon lands, drop the PNGs over these (same names) or adjust the script.

## Presets (`export_presets.cfg`)

| Preset | Platform | Output | Notes |
|---|---|---|---|
| Android | Android | `build/hoop_shoot.apk` | debug, arm64 only, no gradle, the debug keystore — the phone loop |
| Android Play | Android | `build/hoop_shoot.aab` | gradle, AAB, arm64 + armeabi-v7a, the upload keystore from the environment |
| iOS | iOS | `build/ios/hoop_shoot.ipa` (path only: the project is written beside it) | iPhone, portrait (from `display/window/handheld/orientation`), App Store method |

A debug build opens every area (`App.league_gating` off in debug builds,
docs/LEAGUE.md); the release AAB and the Xcode Release scheme gate as
designed. `tests/test_build_config.gd` pins the ids, the team, the gradle /
AAB flags, the empty keystore fields and the shared build number.

## Troubleshooting

- *a Godot instance is running* — close the editor (or a QA run) first.
- *a release build wants a clean tree* — commit or stash; `--debug` builds
  do not care.
- *Target folder does not exist* (iOS) — the script makes `build/ios`; if
  you export from the editor, create it first.
- *Android build template mismatch* — a Godot upgrade; the script
  reinstalls, or `rm -rf android`.
- Signing errors in Xcode — check the account under Xcode → Settings →
  Accounts and that the bundle id is registered to team U8XP33P732.
