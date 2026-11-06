## The store builds' configuration (docs/BUILD.md, 2026-10-24): the project
## version both platforms fall back to, the icons, the three export presets
## with one bundle id and Ross's Apple team, and the build number tools/build.sh
## writes — the same on every preset (a half-applied rewrite shows here).

const BUNDLE_ID := "com.rossgriffus.hoopshoot"
## The iOS id carries the full name (Ross, 2026-10-24: registered with Apple as this).
const IOS_BUNDLE_ID := "com.rossgriffus.hoopshootleague"
const TEAM_ID := "J3X6PY2KB4"


func run(t) -> void:
	# The trailer's capture writes a temporary override.cfg; one left behind
	# would change every run and ship in a build (tools/build.sh refuses too).
	t.ok(not FileAccess.file_exists("res://override.cfg"), "no override.cfg left in the project root")
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	var re := RegEx.new()
	re.compile("^\\d+\\.\\d+\\.\\d+$")
	t.ok(re.search(version) != null, "project version is X.Y.Z (got %s)" % version)
	t.eq(str(ProjectSettings.get_setting("application/config/name", "")), "Hoop Shoot League", "the app is Hoop Shoot League (Ross, 2026-10-24)")
	t.ok(not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)), "…the stock user:// folder (app_userdata/Hoop Shoot League on the Mac)")
	var icon := str(ProjectSettings.get_setting("application/config/icon", ""))
	t.ok(icon != "" and FileAccess.file_exists(icon), "the app icon exists (%s)" % icon)
	for f in ["icon_1024.png", "android_192.png", "adaptive_fg_432.png", "adaptive_bg_432.png"]:
		t.ok(FileAccess.file_exists("res://assets/icon/" + f), "assets/icon/%s exists" % f)

	var cfg := ConfigFile.new()
	t.eq(cfg.load("res://export_presets.cfg"), OK, "export_presets.cfg loads")
	var by_name := {}
	for section in cfg.get_sections():
		if section.ends_with(".options"):
			continue
		by_name[str(cfg.get_value(section, "name", ""))] = section
	for name_ in ["Android", "Android Play", "iOS"]:
		t.ok(by_name.has(name_), "preset %s exists" % name_)
	if not (by_name.has("Android") and by_name.has("Android Play") and by_name.has("iOS")):
		return
	var android: String = by_name["Android"] + ".options"
	var play: String = by_name["Android Play"] + ".options"
	var ios: String = by_name["iOS"] + ".options"
	t.eq(str(cfg.get_value(by_name["Android"], "platform")), "Android", "Android preset is Android")
	t.eq(str(cfg.get_value(by_name["Android Play"], "platform")), "Android", "Play preset is Android")
	t.eq(str(cfg.get_value(by_name["iOS"], "platform")), "iOS", "iOS preset is iOS")
	t.eq(str(cfg.get_value(android, "package/unique_name")), BUNDLE_ID, "Android package id")
	t.eq(str(cfg.get_value(play, "package/unique_name")), BUNDLE_ID, "Play package id")
	t.eq(str(cfg.get_value(android, "package/name")), "Hoop Shoot League", "Android launcher label")
	t.eq(str(cfg.get_value(play, "package/name")), "Hoop Shoot League", "Play launcher label")
	t.eq(str(cfg.get_value(ios, "application/bundle_identifier")), IOS_BUNDLE_ID, "iOS bundle id is the league one")
	t.eq(str(cfg.get_value(ios, "application/app_store_team_id")), TEAM_ID, "iOS signs under Ross's team")
	t.ok(bool(cfg.get_value(play, "gradle_build/use_gradle_build", false)), "the Play preset builds with gradle")
	t.eq(int(cfg.get_value(play, "gradle_build/export_format", 0)), 1, "…as an AAB")
	t.ok(not bool(cfg.get_value(android, "gradle_build/use_gradle_build", false)), "the phone APK preset stays gradle-free (fast)")
	t.eq(str(cfg.get_value(play, "keystore/release", "x")), "", "the upload keystore comes from the environment, never the repo")
	t.eq(str(cfg.get_value(play, "keystore/release_password", "x")), "", "…nor its password")
	t.ok(bool(cfg.get_value(ios, "application/export_project_only", false)), "iOS exports the Xcode project (Ross archives by hand)")
	t.ok(bool(cfg.get_value(ios, "plugins/GodotxRevenueCat", false)), "iOS takes the RevenueCat plugin (ios/plugins/revenuecat, staged by tools/build.sh)")
	t.ok(bool(cfg.get_value(ios, "plugins/AdmobPlugin", false)), "iOS takes the AdMob plugin (ios/plugins/AdmobPlugin.*, staged by tools/build.sh)")
	t.ok(bool(cfg.get_value(ios, "plugins/GameCenter", false)), "iOS takes the Game Center plugin (ios/plugins/gamecenter.*, built by tools/build_gamecenter_plugin.sh)")
	t.ok(bool(cfg.get_value(ios, "entitlements/game_center", false)), "…with the Game Center entitlement (GameKit refuses to sign in without it)")
	t.eq(str(cfg.get_value(ios, "application/min_ios_version", "")), "15.0", "iOS 15+: the RevenueCat SDK's floor, above the AdMob plugin's 14.3")
	t.eq(int(cfg.get_value(ios, "application/export_method_release", -1)), 0, "iOS release method is App Store")
	t.eq(str(cfg.get_value(ios, "application/code_sign_identity_release", "")), "Apple Development", "Release signs as Apple Development: automatic signing swaps in Distribution at upload (an empty field writes Apple Distribution and the archive fails)")
	t.eq(str(cfg.get_value(by_name["iOS"], "export_path")), "build/ios/hoop_shoot.ipa", "iOS lands under build/ios")
	t.eq(str(cfg.get_value(by_name["Android Play"], "export_path")), "build/hoop_shoot.aab", "the AAB lands under build/")
	t.eq(str(cfg.get_value(ios, "icons/icon_1024x1024")), icon, "iOS icon is the project icon")
	t.eq(str(cfg.get_value(android, "version/name", "x")), "", "Android version name falls back to the project version")
	t.eq(str(cfg.get_value(ios, "application/short_version", "x")), "", "iOS short version falls back to the project version")
	# The build number: tools/build.sh writes it to every preset at once.
	var code_a := int(cfg.get_value(android, "version/code", -1))
	var code_p := int(cfg.get_value(play, "version/code", -2))
	var code_i := int(str(cfg.get_value(ios, "application/version", "-3")))
	t.ok(code_a > 0 and code_a == code_p, "both Android presets carry one build number (%d / %d)" % [code_a, code_p])
	t.ok(code_i == code_a or code_i == 0, "iOS carries the same build number (%d) or none yet" % code_i)
	# tests/ is left out of every export (exclude_filter), so a shipped script
	# that names a class_name defined there fails to compile on the device —
	# and a release build reports nothing (Build 390, 2026-11-01: the Ads
	# autoload died over FakeAdsBackend and every match end stalled). Fakes
	# are reached by load("res://tests/…") at run time, never by class.
	var test_classes: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.ends_with(".gd"):
			var m := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)").search(FileAccess.get_file_as_string("res://tests/" + f))
			if m != null:
				test_classes.push_back(m.get_string(1))
	t.ok(test_classes.size() >= 3, "tests/ defines the fake backends (%s)" % str(test_classes))
	for ex in ["art/*", "docs/*", "tests/*"]:
		for p in by_name.values():
			t.ok(str(cfg.get_value(p, "exclude_filter", "")).contains(ex), "preset %s leaves %s out" % [cfg.get_value(p, "name"), ex])
	var offenders: Array[String] = []
	for dir in ["res://game", "res://core", "res://tools"]:
		for path in _gd_files(dir):
			var src := FileAccess.get_file_as_string(path)
			for cls in test_classes:
				if RegEx.create_from_string("(?m)^[^#\\n]*\\b%s\\b" % cls).search(src) != null:
					offenders.push_back("%s → %s" % [path, cls])
	t.eq(offenders, [], "no shipped script names a tests/ class (they are left out of the exports)")
	# The script itself: present, executable, and the only writer of the presets.
	var script := ProjectSettings.globalize_path("res://tools/build.sh")
	t.ok(FileAccess.file_exists(script), "tools/build.sh exists")
	t.ok(FileAccess.get_unix_permissions(script) & 64, "tools/build.sh is executable")


static func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.push_back(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with("."):
			continue
		var sub := dir.path_join(d)
		if sub in ["res://tools/aseprite", "res://tools/blender"]:
			continue
		out.append_array(_gd_files(sub))
	return out
