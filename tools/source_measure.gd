extends RefCounted

## The source-specific uptake measure, frozen by docs/EXPERIMENT_SOURCE.md.
##
## Separate from the probe that drives it for one reason: the self-test must
## exercise THIS code and not a second copy of the arithmetic. A measure whose
## test reimplements it proves only that two functions were written by the same
## hand on the same afternoon.
##
## The question it answers is not "did the reply engage" -- MP1 showed a sham
## satisfies that equally well. It is "does the reply carry material traceable
## to ONE source and not the other", which a sham cannot satisfy by
## construction.

const G := preload("res://scripts/arena/gonzo_recall.gd")

## Chosen from a measured placebo floor, not by taste. At a threshold of 1, a
## reply that never saw the scar takes it up 31.9% of the time and prefers the
## real source over an unrelated one by +6.9 points with nothing injected.
const UPTAKE_MIN := 2
const UPTAKE_MIN_ROBUST := 3
const NGRAM := 6


static func words(t: String) -> Dictionary:
	var out := {}
	for w in t.to_lower().split(" ", false):
		var c := ""
		for i in w.length():
			var ch := w[i]
			if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
				c += ch
		if c.length() > 3 and not G.STOP.has(c):
			out[c] = true
	return out


## Terms distinctive to one source: its own content words, minus anything the
## agent could already see, minus anything the competing source also contains.
## The two sources are disjoint by construction, so a term is never credited to
## both and topical coincidence cannot be scored as source-specific uptake.
static func distinctive(mine: String, visible: String, other: String) -> Dictionary:
	var vis := words(visible)
	var oth := words(other)
	var out := {}
	for w in words(mine):
		if vis.has(w) or oth.has(w):
			continue
		out[w] = true
	return out


static func hits(d: Dictionary, reply: String) -> int:
	var rw := words(reply)
	var n := 0
	for w in d:
		if rw.has(w):
			n += 1
	return n


static func shared_runs(a: String, b: String, n: int) -> Array:
	var out: Array = []
	var aw := a.to_lower().split(" ", false)
	var bw := b.to_lower().split(" ", false)
	var braw := b.split(" ", false)
	if aw.size() < n or bw.size() < n:
		return out
	var seen := {}
	for i in range(aw.size() - n + 1):
		seen[" ".join(aw.slice(i, i + n))] = true
	for i in range(bw.size() - n + 1):
		if seen.has(" ".join(bw.slice(i, i + n))):
			out.append(" ".join(braw.slice(i, i + n)))
	return out


## Which token positions of the reply are inside a run shared with the source.
##
## Index-based, not string replacement. A first version removed each matching
## run with `replace()`, and on a copied stretch longer than the window only the
## FIRST window survived to be removed -- the later windows overlapped text that
## was already gone, so the tail of a verbatim copy stayed in the reply and
## scored as unquoted use. The self-test caught it. Marking positions cannot
## have that bug because removals do not interfere with each other.
##
## Tokens are normalised here, unlike in `shared_runs`, so trailing punctuation
## cannot end a run early. That makes the exclusion slightly more aggressive
## than the detection, which is the safe direction: `hits_unquoted` can then
## only understate genuine use, never inflate it.
static func covered_indices(source: String, reply: String, n: int) -> Dictionary:
	var out := {}
	var aw := _norm_tokens(source)
	var bw := _norm_tokens(reply)
	if aw.size() < n or bw.size() < n:
		return out
	var seen := {}
	for i in range(aw.size() - n + 1):
		seen[" ".join(aw.slice(i, i + n))] = true
	for i in range(bw.size() - n + 1):
		if seen.has(" ".join(bw.slice(i, i + n))):
			for k in range(i, i + n):
				out[k] = true
	return out


static func _norm_tokens(t: String) -> PackedStringArray:
	var out := PackedStringArray()
	for w in t.to_lower().split(" ", false):
		var c := ""
		for i in w.length():
			var ch := w[i]
			if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
				c += ch
		out.append(c)
	return out


## Hits counted only OUTSIDE any shared run with the source.
##
## MP1's suspect clause discarded the whole reply for sharing a run, which is
## the defect being corrected here. Copying removes the copied SPAN and nothing
## more, so a reply that quotes one phrase and then genuinely uses the rest
## still scores for the rest.
static func hits_unquoted(d: Dictionary, reply: String, source: String) -> int:
	var raw := reply.split(" ", false)
	var covered := covered_indices(source, reply, NGRAM)
	var kept := ""
	for i in raw.size():
		if not covered.has(i):
			kept += " " + raw[i]
	return hits(d, kept)


static func copied(source: String, reply: String) -> bool:
	return not shared_runs(source, reply, NGRAM).is_empty()


## A reply naming a turn absent from canonical history is an unsupported
## attribution. Every recall experiment so far has reported zero, and the
## pre-registration keeps that as a hard condition on any positive verdict.
static func unsupported(reply: String, history: Array) -> bool:
	var re := RegEx.new()
	re.compile("(?i)turn\\s+(\\d+)")
	for m in re.search_all(reply):
		var n := int(m.get_string(1))
		var found := false
		for h in history:
			if int(h.get("turn", -1)) == n:
				found = true
				break
		if not found:
			return true
	return false


static func score(reply: String, source: String, d: Dictionary) -> Dictionary:
	var h := hits(d, reply)
	return {
		"u": 1 if h >= UPTAKE_MIN else 0,
		"u3": 1 if h >= UPTAKE_MIN_ROBUST else 0,
		"uq": 1 if hits_unquoted(d, reply, source) >= UPTAKE_MIN else 0,
		"hits": h,
	}


static func rate(rows: Array, arm: String, src: String, field: String) -> float:
	if rows.is_empty():
		return 0.0
	var c := 0
	for r in rows:
		c += int(r["scored"][arm][src][field])
	return 100.0 * float(c) / float(rows.size())


## source_lift(R) = [U(R,A) - U(R,B)] - [U(N,A) - U(N,B)]
##
## The first bracket asks whether the arm prefers its own source. The second is
## the false-positive floor, measured in the same batch on the same
## opportunities. Anything that makes one source easier to hit than the other --
## vocabulary drift, topic overlap, excerpt length -- appears in both and
## cancels. Rule 4 is satisfied by arithmetic rather than by assurance.
static func lift(rows: Array, arm: String, own: String, foreign: String,
		field: String) -> float:
	var treated := rate(rows, arm, own, field) - rate(rows, arm, foreign, field)
	var floor_ := rate(rows, "N", own, field) - rate(rows, "N", foreign, field)
	return treated - floor_


## The permutation null: shuffle which branch produced which scores, recompute,
## repeat. Returns every value so the caller can ask its own questions of the
## distribution instead of being handed one summary.
##
## A FIRST VERSION OF THIS RETURNED ONLY THE WORST VALUE and the gate compared
## it against a fixed bound of 5.0. That voided MP2-B at 240 opportunities. The
## null's spread turned out to be sd 3.95, so the expected maximum of 200 draws
## is 11.2 and the run produced 11.3 -- the gate fired on its own expected
## value, and no dataset could ever have passed it. That is rule 2, broken by
## the guard written to enforce rule 2: a bound was set on a quantity whose
## spread had never been measured.
##
## Sample noise is not brokenness. The two are now asked separately -- see
## `null_mean` for bias and `null_percentile` for significance.
static func scramble_null(rows: Array, arms: PackedStringArray, rng_seed: int,
		reps: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var out: Array = []
	for _rep in reps:
		var shuffled: Array = []
		for r in rows:
			var names := Array(arms)
			for i in range(names.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var tmp = names[i]
				names[i] = names[j]
				names[j] = tmp
			var s := {}
			for k in arms.size():
				s[arms[k]] = r["scored"][names[k]]
			shuffled.append({"scored": s})
		out.append(lift(shuffled, "R", "a", "b", "u"))
	return out


## IS THE ESTIMATOR BIASED? With meaningless labels a crossover that cancels
## correctly has no preferred direction, so this is ~0. It is the question the
## old bound was reaching for, and the only one that means "broken".
static func null_mean(null_dist: Array) -> float:
	if null_dist.is_empty():
		return 0.0
	var t := 0.0
	for v in null_dist:
		t += float(v)
	return t / float(null_dist.size())


## IS THE OBSERVED LIFT DISTINGUISHABLE FROM LABEL NOISE? The percentile of
## |observed| within the null of |lift|. Self-calibrating: it scales with N and
## with the base rates actually observed, so unlike a hand-picked bound it
## cannot be set wrong.
static func null_percentile(null_dist: Array, q: float) -> float:
	if null_dist.is_empty():
		return 0.0
	var a: Array = []
	for v in null_dist:
		a.append(absf(float(v)))
	a.sort()
	var i := int(float(a.size()) * q) - 1
	return float(a[clampi(i, 0, a.size() - 1)])


## THE TEETH. No argument, no flag, no environment variable reaches past this.
## Editorial discipline was tried in MP1 and the same document that warned
## against early reads contained one.
static func decidable(n: int, target: int) -> bool:
	return n >= target
