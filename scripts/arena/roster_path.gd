extends RefCounted
class_name RosterPath

## Where the arena roster lives. One search order, used by every consumer.
##
## THE BUG THIS CLOSES. Six scripts read config/arena-roster.v1.json, and five
## of them hardcoded `../extinct_os/config/arena-roster.v1.json` as their ONLY
## path — a PRIVATE sibling checkout that does not exist in a public clone. So
## alliance_proof, scar_ab_probe, scar_ladder, scar_table and match_scene were
## all dead on arrival for anyone who cloned this repository, each failing with
## its own slightly different message about a file it could never find.
##
## live_match.gd had a two-entry search list and worked, which is exactly how
## the breakage stayed invisible: the one path anybody actually ran was fine.
##
## The same fact written down six times eventually disagrees with itself. This
## is the fifth instance of that pattern in this project, so the search order
## lives here and nowhere else.
##
## Order:
##   1. res://config/arena-roster.v1.json    written by tools/build_roster.gd
##   2. ../extinct_os/config/...             the private development checkout
##
## Public first, deliberately. A contributor with both checkouts should get the
## roster they just built, not a stale one from a sibling directory.

const SEARCH := [
	"res://config/arena-roster.v1.json",
	"res://../extinct_os/config/arena-roster.v1.json",
]

## Absolute path to the first roster that exists, or "" when there is none.
## Returning "" rather than a guess forces callers to report the miss instead
## of failing later on an unreadable file.
static func resolve() -> String:
	for cand in SEARCH:
		var abs := ProjectSettings.globalize_path(cand).simplify_path()
		if FileAccess.file_exists(abs):
			return abs
	return ""


## What to print when resolve() finds nothing. Every consumer used to invent
## its own wording, and most of them named only the private path.
static func missing_hint() -> String:
	var lines := ["roster not found. searched:"]
	for cand in SEARCH:
		lines.append("    " + ProjectSettings.globalize_path(cand).simplify_path())
	lines.append("  build one with:")
	lines.append("    godot --headless --path . --script tools/build_roster.gd")
	lines.append("  (add  -- --balanced  for fewer cold model loads per round)")
	return "\n".join(lines)
