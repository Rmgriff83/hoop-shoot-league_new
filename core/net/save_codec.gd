class_name SaveCodec
extends RefCounted
## The cloud save mirror's wire form (docs/BACKEND.md → Phase 2): a save part
## is its JSON, gzipped, whole. Pure; the server never looks inside.

## The parts that sync, mirrored by hand in server/src/save.ts. The account
## (the secret) and tuning (a dev scratchpad) never do; meta is the device.
const SYNC_PARTS := ["time_trial_scores", "cosmetics", "settings", "campaign", "liveGames", "cards", "progress"]
## Gzipped bytes per part, the server's cap.
const PART_MAX_BYTES := 256 * 1024


static func encode(doc: Dictionary) -> PackedByteArray:
	return JSON.stringify(doc).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)


## {} when the bytes are not a gzipped JSON object.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 18 or bytes[0] != 0x1f or bytes[1] != 0x8b:
		return {}
	var raw := bytes.decompress_dynamic(4 * PART_MAX_BYTES * 8, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


static func is_sync_part(part: String) -> bool:
	return SYNC_PARTS.has(part)
