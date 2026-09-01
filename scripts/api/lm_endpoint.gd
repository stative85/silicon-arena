extends RefCounted
class_name LMEndpoint

## The one place that decides where LM Studio lives.
##
## The URL was hardcoded in four files — lm_studio_client.gd, doctor.gd,
## build_roster.gd and prove.gd. That is the same duplicated-truth pattern that
## produced three production bugs in this project already: a fact written down
## more than once eventually disagrees with itself.
##
## It also meant anyone running LM Studio anywhere other than 127.0.0.1:1234
## had no override at all and had to edit source.
##
## Resolution order:
##   1. SILICON_ARENA_LM_URL   environment variable
##   2. LM_STUDIO_URL          environment variable
##   3. http://127.0.0.1:1234/v1
##
## A bare host:port is accepted and normalised, so all of these work:
##   127.0.0.1:1235
##   http://192.168.1.50:1234
##   http://192.168.1.50:1234/v1

const DEFAULT_URL := "http://127.0.0.1:1234/v1"
const ENV_VARS := ["SILICON_ARENA_LM_URL", "LM_STUDIO_URL"]


static func base_url() -> String:
	for name in ENV_VARS:
		var raw := OS.get_environment(name).strip_edges()
		if raw != "":
			return normalize(raw)
	return DEFAULT_URL


## Accept what people actually type and turn it into a usable base URL.
static func normalize(raw: String) -> String:
	var s := raw.strip_edges()
	if s == "":
		return DEFAULT_URL
	if not (s.begins_with("http://") or s.begins_with("https://")):
		s = "http://" + s
	while s.ends_with("/"):
		s = s.substr(0, s.length() - 1)
	if not s.ends_with("/v1"):
		s += "/v1"
	return s


## True when the endpoint is not the default, so tools can say so rather than
## leaving a user confused about which server they are actually talking to.
static func is_overridden() -> bool:
	return base_url() != DEFAULT_URL
