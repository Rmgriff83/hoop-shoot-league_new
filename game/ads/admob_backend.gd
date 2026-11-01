class_name AdMobBackend
extends AdsBackend
## AdMob through godot-sdk-integrations/godot-admob (docs/BUILD.md → The ads
## plugin; docs/ADS.md): the `AdmobPlugin` native singleton its .aar / .a
## register, driven through the addon's `Admob` node (addons/AdmobPlugin,
## vendored), which this backend builds at `start` from data/ads.json —
## never a node in a scene, so a build without the plugin has nothing to
## resolve. The start: consent (UMP) → the tracking prompt on iOS → the
## SDK → the first interstitial. Only present in the Play (gradle) and iOS
## builds tools/build.sh staged the plugin into; `available()` is false
## everywhere else and `Ads` runs the null backend.

const SINGLETON := "AdmobPlugin"
const NODE_SCRIPT := "res://addons/AdmobPlugin/Admob.gd"
## A failed interstitial load is tried again after this long.
const RETRY_S := 30.0
const ATT_TEXT := "Allowing tracking lets the ads between games pay for Hoop Shoot."

var _node: Node
var _ready_ := false
var _consent_pending := false


func available() -> bool:
	return Engine.has_singleton(SINGLETON) and ResourceLoader.exists(NODE_SCRIPT)


func ready() -> bool:
	return _ready_ and _node != null and bool(_node.call("is_interstitial_ad_loaded"))


## cfg: data/ads.json's block for this platform ({app_id, interstitial}).
func start(cfg: Dictionary) -> void:
	if _node != null or not available():
		return
	var script: GDScript = load(NODE_SCRIPT)
	_node = script.new()
	_node.name = "Admob"
	# The real ids, before the node's _ready reads them; a 13+ game (Ross):
	# PG content, not child-directed.
	_node.set("is_real", true)
	_node.set("ios_real_interstitial_id", str(cfg.get("interstitial", "")))
	_node.set("android_real_interstitial_id", str(cfg.get("interstitial", "")))
	_node.set("max_ad_content_rating", 1)   # AdmobConfig.ContentRating.PG
	_node.set("child_directed", 0)          # TagForChildDirectedTreatment.FALSE
	_node.set("att_enabled", true)
	_node.set("att_text", ATT_TEXT)
	for pair in [
		["initialization_completed", _on_initialized],
		["consent_info_updated", _on_consent_info],
		["consent_info_update_failed", _on_consent_failed],
		["consent_form_loaded", _on_consent_form_loaded],
		["consent_form_failed_to_load", _on_consent_failed],
		["consent_form_dismissed", _on_consent_form_dismissed],
		["tracking_authorization_granted", _on_tracking_done],
		["tracking_authorization_denied", _on_tracking_done],
		["interstitial_ad_loaded", _on_loaded],
		["interstitial_ad_failed_to_load", _on_failed_to_load],
		["interstitial_ad_dismissed_full_screen_content", _on_dismissed],
		["interstitial_ad_failed_to_show_full_screen_content", _on_failed_to_show],
	]:
		if _node.has_signal(pair[0]):
			_node.connect(pair[0], pair[1])
	(Engine.get_main_loop() as SceneTree).root.add_child(_node)
	_consent_pending = true
	_node.call("update_consent_info")


# ---- consent → tracking → the SDK ----------------------------------------------------


func _on_consent_info() -> void:
	if not _consent_pending:
		return
	var consent: Variant = _node.call("get_consent_status")
	var status: int = int(consent.get("status")) if consent != null else 0
	# UserConsent.Status: UNKNOWN 0, NOT_REQUIRED 1, REQUIRED 2, OBTAINED 3.
	if status == 2:
		if bool(_node.call("is_consent_form_available")):
			_node.call("show_consent_form")
		else:
			_node.call("load_consent_form")
	else:
		_after_consent()


func _on_consent_form_loaded() -> void:
	if _consent_pending:
		_node.call("show_consent_form")


func _on_consent_form_dismissed(_error: Variant = null) -> void:
	_after_consent()


func _on_consent_failed(_error: Variant = null) -> void:
	push_warning("ads: consent info unavailable; going on (non-personalised at worst)")
	_after_consent()


func _after_consent() -> void:
	if not _consent_pending:
		return
	_consent_pending = false
	if OS.get_name() == "iOS":
		_node.call("request_tracking_authorization")   # answered granted / denied, either way the SDK starts
	else:
		_node.call("initialize")


func _on_tracking_done() -> void:
	_node.call("initialize")


func _on_initialized(_status: Variant = null) -> void:
	started.emit()


# ---- interstitials -------------------------------------------------------------------


func load_interstitial() -> void:
	if _node == null:
		return
	if bool(_node.call("is_interstitial_ad_loaded")):
		_ready_ = true
		interstitial_ready.emit()
		return
	_node.call("load_interstitial_ad")


func show_interstitial() -> void:
	if not ready():
		interstitial_closed.emit(false)
		return
	_ready_ = false
	_node.call("show_interstitial_ad")


func _on_loaded(_ad_info: Variant = null, _response: Variant = null) -> void:
	_ready_ = true
	interstitial_ready.emit()


func _on_failed_to_load(_ad_info: Variant = null, error: Variant = null) -> void:
	_ready_ = false
	push_warning("ads: interstitial failed to load: %s" % str(error))
	_retry_load()


func _retry_load() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	await tree.create_timer(RETRY_S).timeout
	if _node != null and not _ready_:
		_node.call("load_interstitial_ad")


func _on_dismissed(_ad_info: Variant = null) -> void:
	interstitial_closed.emit(true)


func _on_failed_to_show(_ad_info: Variant = null, error: Variant = null) -> void:
	push_warning("ads: interstitial failed to show: %s" % str(error))
	interstitial_closed.emit(false)
