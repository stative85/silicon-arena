extends Node
class_name ModelPolicy

## The hard model-size law, enforced on the REQUEST PATH.
##
## Why here and not only in config: LM Studio just-in-time loads whatever model
## id a chat request names. Asking for a 12B model IS loading a 12B model. So
## the last line of defence has to sit immediately before the HTTP call, not in
## a file someone can edit or a roster that can drift.
##
## Source of truth is `extinct_os/config/model-catalog.v1.json`, generated from
## `lms ls --json` by `npx tsx tools/buildModelCatalog.ts`. That generator
## applies the policy; this class re-checks it independently so a hand-edited
## catalog cannot smuggle an oversized model through.
##
## Fail CLOSED. If the catalog is missing or unreadable, every request is
## refused and the reason is visible. A silent open door is worse than a
## stopped match.

const CATALOG_PATH := "res://../extinct_os/config/model-catalog.v1.json"
const CATALOG_FALLBACK := "../extinct_os/config/model-catalog.v1.json"

## Mirrors MAX_PARAM_B in extinct_os/src/runtime/modelPolicy.ts.
const MAX_PARAM_B := 7.0

signal model_rejected(model_key: String, reason: String)

var _by_key := {}
var _loaded := false
var _load_error := ""
var _rejections := 0


func _ready() -> void:
	load_catalog()


func load_catalog() -> bool:
	_by_key.clear()
	_loaded = false
	_load_error = ""

	var text := _read_catalog()
	if text == "":
		_load_error = "catalog not readable at %s" % CATALOG_PATH
		push_warning("[model-policy] " + _load_error + " — ALL model requests will be refused")
		return false

	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary) or not parsed.has("models"):
		_load_error = "catalog malformed (no `models` array)"
		push_warning("[model-policy] " + _load_error + " — ALL model requests will be refused")
		return false

	for m in parsed["models"]:
		if m is Dictionary and str(m.get("modelKey", "")) != "":
			_by_key[str(m["modelKey"])] = m

	_loaded = true
	print("[model-policy] catalog loaded: %d models, ceiling %.0fB" % [_by_key.size(), MAX_PARAM_B])
	return true


func _read_catalog() -> String:
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f != null:
		var t := f.get_as_text()
		f.close()
		return t
	# res:// cannot climb out of the project; resolve against the real path.
	var abs := ProjectSettings.globalize_path("res://").path_join(CATALOG_FALLBACK).simplify_path()
	f = FileAccess.open(abs, FileAccess.READ)
	if f != null:
		var t := f.get_as_text()
		f.close()
		return t
	return ""


## Returns "" when the request is permitted, otherwise a human-readable reason.
## This is the function the client calls before every chat request.
## Resolve a runtime model id to a catalog key.
##
## The arena stores full GGUF paths in presets
##   "lmstudio-community/Qwen3.5-9B-GGUF/Qwen3.5-9B-Q4_K_M.gguf"
## while the catalog is keyed by short model key
##   "qwen/qwen3.5-9b"
## Without this, every preset model resolves to "not in catalog" and the law
## refuses the entire roster instead of just the oversized models.
func resolve_key(model_id: String) -> String:
	var raw := model_id.strip_edges()
	if raw == "":
		return ""
	if _by_key.has(raw):
		return raw

	var lower := raw.to_lower()
	if _by_key.has(lower):
		return lower

	# "<publisher>/<Repo-GGUF>/<file>.gguf" -> "repo"
	var parts := lower.split("/", false)
	var base := lower
	if parts.size() >= 2:
		base = parts[parts.size() - 2]
	if base.ends_with("-gguf"):
		base = base.substr(0, base.length() - 5)

	if _by_key.has(base):
		return base
	for k in _by_key.keys():
		var tail: String = String(k).get_slice("/", String(k).get_slice_count("/") - 1)
		if tail == base:
			return k
	return ""


## Last-resort size read from the id itself, for models absent from the catalog.
## Returns -1.0 when no size can be read, which callers must treat as a refusal.
func params_from_id(model_id: String) -> float:
	var re := RegEx.new()
	re.compile("(?i)([0-9]+(?:[.][0-9]+)?)[ _-]*[bB]([^a-zA-Z0-9]|$)")
	var best := -1.0
	for m in re.search_all(model_id):
		var v := float(m.get_string(1))
		if v > best:
			best = v
	return best


func check(model_key: String) -> String:
	if not _loaded:
		return "model catalog unavailable (%s) — refusing every request rather than risking a load" % _load_error

	var raw := model_key.strip_edges()
	if raw == "":
		return "empty model id"

	var key := resolve_key(raw)
	if key == "":
		# Not in the catalog under any spelling. Read the size out of the id
		# rather than refusing the whole roster; refuse if it cannot be read.
		var guessed := params_from_id(raw)
		if guessed < 0.0:
			return "\"%s\" is not in the catalog and its size cannot be read — refusing" % raw
		if guessed > MAX_PARAM_B:
			return "\"%s\" is %.1fB by name, above the %.0fB ceiling — refusing to load" % [raw, guessed, MAX_PARAM_B]
		return ""

	var m: Dictionary = _by_key[key]

	# Independent re-check of the ceiling: never trust the `eligible` flag alone.
	var params = m.get("paramsB", null)
	if params == null:
		return "\"%s\" has no confident parameter count — ineligible" % key
	var p := float(params)
	if p > MAX_PARAM_B:
		return "\"%s\" is %.1fB, above the %.0fB ceiling — refusing to load" % [key, p, MAX_PARAM_B]

	if not bool(m.get("eligible", false)):
		return "\"%s\" is ineligible: %s" % [key, str(m.get("exclusionReason", "no reason recorded"))]

	return ""


## Convenience: check and emit. Returns true when the request may proceed.
func permit(model_key: String) -> bool:
	var reason := check(model_key)
	if reason == "":
		return true
	_rejections += 1
	push_warning("[model-policy] REFUSED %s" % reason)
	model_rejected.emit(model_key, reason)
	return false


func is_loaded() -> bool:
	return _loaded


func rejection_count() -> int:
	return _rejections


func eligible_count() -> int:
	var n := 0
	for k in _by_key:
		if bool(_by_key[k].get("eligible", false)):
			n += 1
	return n


func describe(model_key: String) -> Dictionary:
	return _by_key.get(model_key, {})
