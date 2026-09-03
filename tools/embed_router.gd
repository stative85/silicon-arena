extends RefCounted
class_name GonzoEmbed

## Semantic scar selection, and the bookkeeping that stops it lying.
##
## THE POINT OF THIS FILE IS NOT THE COSINE. Similarity is four lines. What
## takes a file is making sure a vector is never compared against a vector from
## a different space, because that failure is silent: it returns a confident
## number, it looks like a working router, and it is wrong.
##
## That is the same failure class as an unsupported quote. It is invisible to
## the viewer and it cannot be caught by looking at output.
##
## The embedder is OPTIONAL INFRASTRUCTURE. Every path here fails open to
## distance recall. A stranger who never loads an embedding model gets working
## Gonzo memory, because distance is the proven baseline
## (docs/EXPERIMENT_TOURNAMENT.md), not an embarrassing fallback.
##
## VRAM: zero. The model runs under the CPU-only llama.cpp runtime, which is
## the only way an 84 MB router genuinely takes nothing from an 8 GB card.
## See docs/EXPERIMENT_EMBEDDING.md -- `--gpu off` alone still costs 299 MiB
## of CUDA context.

const MODEL_ID := "text-embedding-nomic-embed-text-v1.5@q4_k_m"
const DIMENSION := 768
const SCHEMA_VERSION := 1

## Nomic is trained asymmetrically. The current moment is a QUERY, a stored
## scar is a DOCUMENT. Using one prefix for both quietly degrades retrieval.
const QUERY_PREFIX := "search_query: "
const DOC_PREFIX := "search_document: "


static func text_hash(text: String) -> String:
	return text.sha256_text()


## Everything needed to prove a cached vector still describes what it claims to.
static func stamp(vec: PackedFloat32Array, source_turn_id: int,
		source_text: String) -> Dictionary:
	return {
		"vector": vec,
		"embedding_model_id": MODEL_ID,
		"embedding_dimension": vec.size(),
		"embedding_schema_version": SCHEMA_VERSION,
		"source_turn_id": source_turn_id,
		"source_text_hash": text_hash(source_text),
	}


## ANY mismatch invalidates. Not a warning, not a best effort -- invalid.
##
## Five ways a cached vector can be a lie: a different model, a different
## schema, a truncated or padded vector, a vector filed against the wrong turn,
## or text that has changed since it was embedded. All five are checked, because
## the whole reason this cache exists is that re-embedding is expensive, and a
## cache you cannot trust is worse than no cache.
static func valid(entry: Dictionary, source_turn_id: int,
		source_text: String) -> bool:
	if entry.is_empty():
		return false
	if str(entry.get("embedding_model_id", "")) != MODEL_ID:
		return false
	if int(entry.get("embedding_schema_version", -1)) != SCHEMA_VERSION:
		return false
	if int(entry.get("embedding_dimension", -1)) != DIMENSION:
		return false
	if int(entry.get("source_turn_id", -1)) != source_turn_id:
		return false
	if str(entry.get("source_text_hash", "")) != text_hash(source_text):
		return false
	var v = entry.get("vector", null)
	if not (v is PackedFloat32Array) or v.size() != DIMENSION:
		return false
	return true


## Refuses rather than guesses. A zero vector, a dimension mismatch or a
## degenerate magnitude returns 0.0, which loses every comparison, so a broken
## vector can never win a selection.
static func cosine(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != b.size() or a.is_empty():
		return 0.0
	var dot := 0.0
	var na := 0.0
	var nb := 0.0
	for i in a.size():
		dot += a[i] * b[i]
		na += a[i] * a[i]
		nb += b[i] * b[i]
	if na <= 0.0 or nb <= 0.0:
		return 0.0
	return dot / (sqrt(na) * sqrt(nb))


## Pick the most similar cached scar. Returns -1 when it cannot answer, which
## the caller must read as "use distance", never as "no good match".
##
## A scar with no valid cached vector is SKIPPED rather than treated as
## dissimilar. Silently ranking an un-embedded scar last would let a cache miss
## masquerade as a semantic judgement.
static func best_index(query: PackedFloat32Array, cached: Array) -> int:
	if query.size() != DIMENSION:
		return -1
	var best := -1
	var best_score := -2.0
	for i in cached.size():
		var e = cached[i]
		if not (e is Dictionary) or e.is_empty():
			continue
		var v = e.get("vector", null)
		if not (v is PackedFloat32Array) or v.size() != query.size():
			continue
		var s := cosine(query, v)
		if s > best_score:
			best_score = s
			best = i
	return best


## Parse an OpenAI-shaped embeddings response. Returns an empty array on
## anything unexpected, so a malformed reply falls open instead of propagating
## a half-built vector.
static func parse_response(body: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var p = JSON.parse_string(body)
	if typeof(p) != TYPE_DICTIONARY or not p.has("data"):
		return out
	var data = p["data"]
	if typeof(data) != TYPE_ARRAY or data.is_empty():
		return out
	var first = data[0]
	if typeof(first) != TYPE_DICTIONARY or not first.has("embedding"):
		return out
	var emb = first["embedding"]
	if typeof(emb) != TYPE_ARRAY:
		return out
	for x in emb:
		out.append(float(x))
	return out
