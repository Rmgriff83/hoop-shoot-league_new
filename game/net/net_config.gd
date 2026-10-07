class_name NetConfig
extends RefCounted
## Where the API lives (docs/BACKEND.md). No secrets: the only credential is
## the per-device secret the game mints at runtime. Desktop (the editor, QA)
## talks to a local `wrangler dev`; a phone talks to the deployed Worker.
## `-- --api=URL` overrides either; `-- --no-net` turns networking off.

const DEV_URL := "http://127.0.0.1:8787"
## The deployed Worker (`cd server && npx wrangler deploy --env production`
## prints it). Empty = no server yet: the game stays on its device boards.
const PROD_URL := "https://hoop-shoot-api.rmgriffus.workers.dev"


static func base_url() -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--api="):
			return str(a).trim_prefix("--api=").rstrip("/")
	return PROD_URL if OS.has_feature("mobile") else DEV_URL


static func disabled_by_args() -> bool:
	return OS.get_cmdline_user_args().has("--no-net")


## The build the payload names (`application/config/version`, or dev).
static func version() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	return v if v != "" else "dev"
