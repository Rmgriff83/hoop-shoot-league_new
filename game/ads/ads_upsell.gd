class_name AdsUpsell
extends RefCounted
## The nudge after an interstitial (docs/ADS.md): once every few ads, the
## results screen's side toast says the Ticket Store removes them.

const SHOW_S := 4.0


## `chrome`: the screen's full-rect control (a side toast measures its edges by its parent).
static func maybe_toast(chrome: Control) -> void:
	if not Ads.take_upsell():
		return
	var toast := Toast.new(RetroTheme.LIGHT["gold"], UiLayout.hud_y(Hud.TOAST_Y), Toast.Mode.SIDE, Hud.toast_side())
	toast.name = "AdsUpsell"
	toast.set_small(StoreCopy.upsell(), StoreCopy.upsell_sub(), "icon_ticket")
	chrome.add_child(toast)
	toast.show_once.call_deferred(SHOW_S)
