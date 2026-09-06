extends RefCounted
class_name PitCanonText

## Canonical identity that survives representation.
##
## Run 3 VOID record: docs/results/PIT_A_RUN3_VOID.md
##
## THE LAW THIS ENFORCES:
##
##   CANONICAL IDENTITY MUST BE REPRESENTATION-INVARIANT. For every
##   JSON-representable value: dictionary insertion order must not affect
##   canonical text or hash; JSON serialise-then-parse must not affect it;
##   journal append-then-read must not affect it; and live apply and replay
##   apply must produce identical identity.
##
## WHY. PitWorld.canonical_text() sorted keys one level deep and stringified
## nested values with str(), which preserves INSERTION ORDER. Falcon-H1 proposed
## a MUTATE whose props held a nested object, the journal round-trip reordered
## its keys, and the same world hashed two different ways. The run aborted at
## cycle 2 and 900 earlier cycles became untrustworthy.
##
## `str(Dictionary)` MAY NEVER APPEAR INSIDE IDENTITY COMPUTATION. Not here, not
## in PitWorld, not anywhere a hash is derived. It is convenient, it is stable
## most of the time, and "most of the time" is how three runs died.
##
## FAIL CLOSED ON THE UNKNOWN. A Variant this function does not recognise is not
## silently stringified -- it returns the poison marker, and callers must treat a
## poisoned canonical text as a hard error rather than a slightly odd hash.

## Returned when a value cannot be canonicalised. Callers must refuse it.
const POISON := "<<NON_CANONICALISABLE>>"

## Numbers are frozen to ONE representation. A JSON round-trip in this engine
## turns 1 into 1.0, and identity must not depend on which side of the parser a
## number happens to be sitting. Integral floats collapse to their integer form;
## everything else uses a fixed-precision decimal. Relying on what the engine
## "happens to do today" is exactly the assumption Run 3 died on.
const FLOAT_DECIMALS := 10


static func canonical(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			return str(int(value))
		TYPE_FLOAT:
			var f := float(value)
			if not is_finite(f):
				return POISON
			# 1.0 and 1 are the same world. JSON cannot tell them apart on the
			# way back, so identity must not either.
			if f == floor(f) and absf(f) < 9.0e15:
				return str(int(f))
			return String.num(f, FLOAT_DECIMALS)
		TYPE_STRING, TYPE_STRING_NAME:
			return _quote(str(value))
		TYPE_DICTIONARY:
			var d: Dictionary = value
			var keys: Array = []
			for k in d.keys():
				# Non-string keys have no JSON representation and therefore no
				# stable identity across a round-trip.
				if typeof(k) != TYPE_STRING and typeof(k) != TYPE_STRING_NAME:
					return POISON
				keys.append(str(k))
			keys.sort()
			var parts: Array = []
			for k in keys:
				var inner := canonical(d[k])
				if inner == POISON:
					return POISON
				parts.append(_quote(k) + ":" + inner)
			return "{" + ",".join(PackedStringArray(parts)) + "}"
		TYPE_ARRAY:
			# ORDER IS MEANING in an array and is preserved. Sorting one would
			# make [a,b] and [b,a] the same world, which they are not.
			var a: Array = value
			var items: Array = []
			for v in a:
				var inner2 := canonical(v)
				if inner2 == POISON:
					return POISON
				items.append(inner2)
			return "[" + ",".join(PackedStringArray(items)) + "]"
	return POISON


static func is_poisoned(text: String) -> bool:
	return text.find(POISON) != -1


## JSON-style escaping, written out rather than borrowed so the escaping cannot
## change underneath identity when an engine implementation does.
static func _quote(s: String) -> String:
	var out := "\""
	for i in s.length():
		var c := s[i]
		match c:
			"\"":
				out += "\\\""
			"\\":
				out += "\\\\"
			"\n":
				out += "\\n"
			"\r":
				out += "\\r"
			"\t":
				out += "\\t"
			_:
				var code := s.unicode_at(i)
				if code < 0x20:
					out += "\\u%04x" % code
				else:
					out += c
	return out + "\""
