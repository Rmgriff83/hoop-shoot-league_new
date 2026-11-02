# Building for the stores

The app is **Hoop Shoot League** (Ross, 2026-10-24): `application/config/name`
is the iOS display name and the Android presets' `package/name` the launcher
label; the Android package stays `com.rossgriffus.hoopshoot` (installed on the
phone), the iOS bundle id is `com.rossgriffus.hoopshootleague` (registered with
Apple under that name), and the Mac's `user://` folder
followed the name: `~/Library/Application Support/Godot/app_userdata/Hoop Shoot League/`
(the old `Hoop Shoot` folder was copied over once, 2026-10-24; QA snaps land in its `qa/`).

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

The preset carries the team (`J3X6PY2KB4`) and the bundle id
(`com.rossgriffus.hoopshootleague`), with automatic signing: no profiles in
the preset, and `code_sign_identity_release="Apple Development"` — Xcode's
automatic signing builds the archive with the development identity and
swaps in Apple Distribution at upload; an empty field makes Godot write
"Apple Distribution" and the archive fails with "conflicting provisioning
settings" (2026-10-24). The Apple ID that owns the team must be signed in
under Xcode → Settings → Accounts, or the archive stops at "No Account for
Team". The export writes the Xcode project only
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

### The store plugin (RevenueCat, 2026-10-31)

The ticket store (docs/ECONOMY.md → Ticket packs) buys through RevenueCat's
native SDKs by way of **godot-x/revenuecat 2.6.0** (MIT; Godot 4.7, iOS
15+, Android minSdk 24). Only its two small scripts are in the repo
(`addons/godotx_revenue_cat/`, enabled in `project.godot`); the ~240 MB of
binaries live outside it like the keystore:

```
~/.config/hoop_shoot/revenuecat/android/revenue_cat/   revenue_cat.debug.aar, revenue_cat.release.aar
~/.config/hoop_shoot/revenuecat/ios/plugins/revenue_cat/ revenue_cat.gdip + GodotxRevenueCat / RevenueCat / RevenueCatUI .xcframework
```

(**`tools/fetch_store_plugin.sh`** puts them there: the release zip, pinned by
version and SHA-256 — Godot's stand-in for a lockfile). `tools/build.sh`
copies them into `android/revenue_cat/` and `ios/plugins/revenue_cat/`
(both gitignored) before every export, dropping a `.gdignore` into each so
the editor's resource scan skips the frameworks (without it the 137 MB of
Swift ABI `.json` inside the xcframeworks lands in the pck — the exports
find the `.gdip` / `.aar` through the filesystem, so they still ship; the
script fails the export if a plugin file is packed). The Android side rides the **gradle**
build only — the Play preset; the phone-deploy "Android" preset stays
gradle-free (Ross, 2026-10-31), so phone deploys run the stub store. The iOS
preset carries `plugins/GodotxRevenueCat=true`. Missing binaries are a
warning, not a failure: the game then runs its null store backend.

The SDK keys — RevenueCat's *public* `appl_…` / `goog_…` per app — are read
from **`store_keys.json`** at the project root (gitignored; copy
`store_keys.example.json`). Absent or unfilled, the store is the stub too.
docs/BACKEND.md → Ticket store has the dashboard and store-console setup.

### What the exports leave out (and the silent failure it causes)

Every preset's `exclude_filter` drops `art/*`, `docs/*`, `tests/*`,
`tools/aseprite/*`, `tools/blender/*` and `build/*`. A shipped script that
names a `class_name` defined under `tests/` (the fake backends) therefore
**fails to compile on the device**, taking its autoload and every script
that depends on it down with it — and a release export template reports
nothing: GDScript runtime errors are only printed in debug builds, so the
calling function just stops. That was Build 390's stall at every match end
(2026-11-01): `Ads` named `FakeAdsBackend`, the `Ads` autoload never
existed, and `App.finish_run` died silently at `Ads.before_results`. The
rules now: fakes are reached by `load("res://tests/…")` at run time, never
by class (`tools/qa_driver.gd` ships as an autoload, so this holds for it
too); `tests/test_build_config.gd` fails on any `game/`, `core/` or `tools/`
script that names a `tests/` class. When a device build misbehaves with no
error in Xcode's console, suspect a compile failure first: hide the
excluded files and `load()` the script headless to reproduce.

### The ads plugin (AdMob, 2026-11-01)

Interstitials (docs/ADS.md) come through **godot-sdk-integrations/godot-admob
v7.0** (MIT; tested on Godot 4.7; Google Mobile Ads 24.9.0 on Android,
12.14.0 on iOS). The addon's GDScript is **vendored** — `addons/AdmobPlugin`
(the `Admob` node, the export plugin, the models) and `addons/GMPShared` —
and enabled in project.godot; the binaries live outside the repo:

```
~/.config/hoop_shoot/admob/android/bin/{debug,release}/AdmobPlugin-*.aar
~/.config/hoop_shoot/admob/ios/plugins/AdmobPlugin.gdip + AdmobPlugin.{debug,release}.xcframework
```

**`tools/fetch_ads_plugin.sh`** puts them there (the release zip, pinned by
version and SHA-256; `--vendor` re-copies the addon for a new release).
`tools/build.sh` copies the .aar pair into `addons/AdmobPlugin/bin/` and the
iOS files into `ios/plugins/` (all gitignored, `.gdignore`d so nothing of
them is packed), and **writes `addons/AdmobPlugin/{ios,android}_export.cfg`
from `data/ads.json`** (the AdMob app id, `is_real`, the ATT text) — the
ids have one home. The iOS preset carries `plugins/AdmobPlugin=true` and
`application/min_ios_version="15.0"` (RevenueCat's floor; the AdMob plugin
wants 14.3+). Missing binaries: a warning, no ads.

Two things happen at the iOS export that the RevenueCat plugin never
needed: the export plugin injects `GADApplicationIdentifier`,
`NSUserTrackingUsageDescription` (ATT), the SKAdNetwork ids and an ATS
allowance into the plist, and it pulls the **Google Mobile Ads SDK into
the Xcode project by Swift Package Manager** — a Ruby script using the
`xcodeproj` gem (this Mac has it from CocoaPods; `gem install xcodeproj`
otherwise), then `xcodebuild -resolvePackageDependencies` (network).
`build.sh` fails the export when the plugin was staged but no SPM line
shows in the log. Xcode resolves the package again when the project opens.
The Android side rides the gradle (Play) build only, like the store; phone
deploys show no ads. With placeholder ids in `data/ads.json` the plugin
ships inert: `AdMobBackend.available()` is true on the phone but
`Ads.platform_cfg()` is empty, so the SDK never starts.

### The Game Center plugin (2026-11-01)

Game Center sign-in (docs/BACKEND.md → Platform identity) rides the official
**godotengine/godot-ios-plugins `gamecenter`** plugin (MIT), whose
`request_identity_verification_signature` is exactly Apple's
`fetchItems(forIdentityVerificationSignature:)` with the team player id.
That repo publishes binaries for Godot 3 only, so its six source files are
**vendored** in `tools/ios_plugins/gamecenter/` (`.gdignore`d: the editor
never scans them, no export packs them; `CREDITS.md` lists the commit and
our three patches — GameKit imported before Godot's headers, the root view
controller through the window scene, the signature event handed to the main
queue; the `.gdip` drops `capabilities=["gamekit"]`) and built here:

```
tools/build_gamecenter_plugin.sh      # once per source/engine change (--force to redo)
~/.config/hoop_shoot/gamecenter/src/godot          the Godot 4.7.1-stable source (headers only; ~70 MB, fetched once, SHA-256 pinned)
~/.config/hoop_shoot/gamecenter/ios/plugins/gamecenter.gdip + gamecenter.{debug,release}.xcframework
```

The script needs Xcode's command line tools and `scons` (`brew install
scons`) — scons only writes the engine's three generated headers
(`core/version_generated.gen.h`, `core/extension/gdextension_interface.gen.h`,
`core/disabled_classes.gen.h`), never a full engine build; clang then
compiles the plugin for `arm64` at `-miphoneos-version-min=15.0` with
`-fobjc-arc` (the source uses `__weak`), `libtool` and `xcodebuild
-create-xcframework` wrap it (device slice only: the archive needs no
simulator). The output is stamped with the vendored source's hash and the
engine tag, so a re-run is a no-op until one changes. `tools/build.sh`
copies the three files into `ios/plugins/` (gitignored, `.gdignore`d) like
the other two plugins; missing, it warns and the game runs the null
platform backend (no sign-in, no restore). The iOS preset carries
`plugins/GameCenter=true` and **`entitlements/game_center=true`** — GameKit
refuses to authenticate without `com.apple.developer.game-center` in the
entitlements — and Ross switches Game Center on for the app in App Store
Connect. GameKit links through the `.gdip`'s `system=["GameKit.framework"]`.

## The icon

`assets/icon/icon_1024.png` is Ross's final icon (design 46b NEON BALL,
2026-10-28: the neon basketball — one orange tube with a white-hot core
tracing the outline and the four seams, a stepped glow on the bricks — on
the brick wall, no text; drawn on a 128-cell grid, exported at 1024, opaque
and square since iOS masks the corners). It comes from the design
project's `export/app_icon/icon_1024x1024.png` with the C2PA chunk
stripped. iOS and `application/config/icon` take it as is (the preset
resizes it nearest-neighbour). The Android files beside it are derived by
`tools/render_icon.gd`
(`godot --headless --path . -s tools/render_icon.gd && godot --headless --path . --import`):
`android_192.png` (the legacy launcher icon, nearest), and the adaptive
pair at 2.7 px per cell — `adaptive_bg_432.png` is a brick wall tiled from
the icon's own ball-free border bricks (the wall repeats every 16 cells),
`adaptive_fg_432.png` is only the ball and its glow on transparency, on
the same cell grid so the mortar lines meet; the tube spans ~243 px and the
glow ~259, inside Android's 264 px safe circle. A new icon: drop the 1024
over the file and rerun the script. No monochrome (themed-icon) layer yet.

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
  Accounts and that the bundle id is registered to team J3X6PY2KB4.
