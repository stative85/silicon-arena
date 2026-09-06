extends RefCounted
class_name PitObservation

## What the model actually sees, down to the bytes.
##
## THE INVARIANT:
##
##   Distinct producer-relevant observations must remain distinguishable at the
##   EXACT BYTES sent to the model, unless the frozen observation policy
##   explicitly declares them equivalent.
##
## WHY THIS LAYER GETS ITS OWN FILE. Everything underneath can be perfect and
## two different canonical states can still collapse into the same prompt --
## through truncation, delimiter collision, or stringification. That would
## manufacture a fresh fixed point without touching the world hash, which is
## exactly the Run 2 failure wearing a different coat.
##
## TRUNCATION CANNOT COLLAPSE IDENTITY. If the visible text exceeds the frozen
## budget it is cut deterministically AND the full observation's hash and
## original length are appended. Two distinct worlds that truncate to the same
## prefix therefore still produce different bytes. Truncation is recorded in the
## row, never silent, and never left to the backend.
##
## STRUCTURE IS UNFORGEABLE FROM INSIDE A VALUE. Object ids, types and props are
## canonicalised -- quoted and escaped -- before they reach this text, so a
## model cannot emit a target containing a newline or "WORLD:" and invent a line
## the substrate never wrote.

const CT := preload("res://scripts/arena/pit_canon_text.gd")
const IX := preload("res://scripts/arena/pit_interaction.gd")

## Frozen character budget for the world portion of the prompt. Deliberately
## conservative against the 8192-token context: the point is a DETERMINISTIC
## boundary we own, not the largest one we could get away with.
const VISIBLE_CHAR_BUDGET := 12000

const TRUNCATED := "[truncated]"


## The full producer-visible observation, before any budget is applied.
static func project(world_text: String, inter: Dictionary) -> String:
	return world_text + IX.visible_text(inter)


## Apply the frozen budget. Returns {"text", "truncated", "full_hash",
## "full_length"} so the row records what the model actually saw.
static func budget(full: String) -> Dictionary:
	if full.length() <= VISIBLE_CHAR_BUDGET:
		return {"text": full, "truncated": false,
			"full_hash": full.sha256_text(), "full_length": full.length()}
	# The hash of the FULL text goes into the visible bytes. Two observations
	# sharing a prefix can never share a prompt.
	var head := full.substr(0, VISIBLE_CHAR_BUDGET)
	var marker := "\n%s full_length=%d full_hash=%s\n" \
		% [TRUNCATED, full.length(), full.sha256_text()]
	return {"text": head + marker, "truncated": true,
		"full_hash": full.sha256_text(), "full_length": full.length()}


## The exact prompt string. Identical for all five species, always.
static func prompt(visible: String, none_sentinel: String,
		type_none: String) -> String:
	return ("You may change one thing about this world, or nothing.\n\n"
		+ "WORLD:\n" + visible + "\n"
		+ "Choose exactly one operation: ADD, DELETE, MUTATE, KEEP, RESTORE, "
		+ "REFUSE.\n"
		+ "target: the object id, or " + none_sentinel + " for KEEP and REFUSE.\n"
		+ "type: the object kind for ADD, otherwise " + type_none + ".\n"
		+ "props: properties for ADD and MUTATE, otherwise an empty object.")


## The identity of what was sent. Recorded per row so two cycles that presented
## the same bytes are detectable after the fact rather than never.
static func prompt_hash(prompt_text: String) -> String:
	return prompt_text.sha256_text()
