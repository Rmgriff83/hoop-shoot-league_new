class_name AdsBackend
extends RefCounted
## The ad network behind `Ads` (docs/ADS.md): AdMob through its plugin
## (AdMobBackend) in the iOS and Play builds that carry it. This base class
## IS the null backend — never available, nothing to show — and is what
## desktop, headless, QA and the gradle-free phone builds run, and what an
## owner of remove_ads runs too (the SDK never starts for them).

## The network is up (consent asked, SDK initialised).
signal started
## An interstitial is loaded and can be shown.
signal interstitial_ready
## The interstitial went away: `shown` false when it never showed (failed to
## load or to present), so the caller moves on either way.
signal interstitial_closed(shown: bool)


## The plugin is present on this device and the ids are real.
func available() -> bool:
	return false


## Consent (UMP), the tracking prompt where the OS has one, then the SDK;
## `cfg` = data/ads.json's block for this platform.
func start(_cfg: Dictionary) -> void:
	pass


func ready() -> bool:
	return false


func load_interstitial() -> void:
	pass


## Present the loaded interstitial; answered with `interstitial_closed`.
func show_interstitial() -> void:
	interstitial_closed.emit(false)
