@tool
extends EditorPlugin
## The Play Games Services plugin in the Android gradle export (docs/BUILD.md →
## The Play Games plugin). The binaries are godot-sdk-integrations/
## godot-play-game-services (tools/fetch_play_games_plugin.sh pins the release),
## staged by tools/build.sh into android/play_games/; this addon replaces the
## plugin's own export script, which keeps the game id in export_presets.cfg.
## Here it comes from data/play_games.json: the id is written to a string
## resource in the gradle template (Google reads APP_ID as a resource — a bare
## number in the manifest is parsed as an int and rejected) and the manifest
## gets the meta-data that points at it. A placeholder id leaves the plugin
## out entirely — no .aar, no dependencies, no meta-data — so the singleton is
## absent on the phone and Platform runs its null backend; shipping the SDK
## without an APP_ID would throw at PlayGamesSdk.initialize.

const PLUGIN_NAME := "PlayGamesPlugin"

var _android: AndroidExportPlugin


func _enter_tree() -> void:
	_android = AndroidExportPlugin.new()
	add_export_plugin(_android)


func _exit_tree() -> void:
	remove_export_plugin(_android)
	_android = null


class AndroidExportPlugin extends EditorExportPlugin:
	const CONFIG := "res://data/play_games.json"
	## Relative to res://addons, as Godot wants library paths.
	const AAR_DEBUG := "../android/play_games/play_games.debug.aar"
	const AAR_RELEASE := "../android/play_games/play_games.release.aar"
	const RES_FILE := "res://android/build/res/values/play_games.xml"
	const DEPENDENCIES := ["com.google.code.gson:gson:2.11.0", "com.google.android.gms:play-services-games-v2:21.0.0"]
	const META := "<meta-data android:name=\"com.google.android.gms.games.APP_ID\" android:value=\"@string/game_services_project_id\"/>"

	var _game_id := ""
	var _shipping := false


	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid


	func _get_name() -> String:
		return PLUGIN_NAME


	## data/play_games.json's game id, "" for a placeholder or anything but digits.
	static func game_id() -> String:
		if not FileAccess.file_exists(CONFIG):
			return ""
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		if not parsed is Dictionary:
			return ""
		var id := str(Dictionary(parsed).get("game_id", ""))
		return id if id != "" and id.is_valid_int() and not id.contains("REPLACE_ME") else ""


	func _export_begin(_features: PackedStringArray, is_debug: bool, _path: String, _flags: int) -> void:
		_shipping = false
		if not _supports_platform(get_export_platform()):
			return
		_game_id = game_id()
		if _game_id == "":
			print("[%s] data/play_games.json carries a placeholder game id: the Play Games plugin stays out of this build" % PLUGIN_NAME)
			return
		var aar := "res://android/play_games/" + (AAR_DEBUG if is_debug else AAR_RELEASE).get_file()
		if not FileAccess.file_exists(aar):
			print("[%s] no %s (tools/fetch_play_games_plugin.sh, then tools/build.sh stages it): the Play Games plugin stays out of this build" % [PLUGIN_NAME, aar])
			return
		var dir := RES_FILE.get_base_dir()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var f := FileAccess.open(RES_FILE, FileAccess.WRITE)
		if f == null:
			printerr("[%s] cannot write %s" % [PLUGIN_NAME, RES_FILE])
			return
		f.store_string("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<!-- Written by addons/PlayGamesPlugin from data/play_games.json at export: do not edit. -->\n<resources>\n\t<string translatable=\"false\" name=\"game_services_project_id\">%s</string>\n</resources>\n" % _game_id)
		f.close()
		_shipping = true
		print("[%s] game id %s → %s" % [PLUGIN_NAME, _game_id, RES_FILE])


	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		if not _shipping:
			return PackedStringArray()
		return PackedStringArray([AAR_DEBUG if debug else AAR_RELEASE])


	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		if not _shipping:
			return PackedStringArray()
		return PackedStringArray(DEPENDENCIES)


	func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return META if _shipping else ""
