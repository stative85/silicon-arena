extends SceneTree

## Does the VRAM estimator produce numbers that mean anything?
##
##   godot --headless --path . --script scripts/arena/vram_selftest.gd
##
## Deterministic: pure arithmetic, no GPU and no LM Studio.
##
## These numbers decide whether a roster swaps or stays resident, which is the
## dominant cost in the project. A typo in the quantisation table would silently
## mis-size every roster and nothing else would notice, so the table is pinned
## against real cases rather than merely exercised.

const V := preload("res://scripts/arena/vram.gd")

var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("   ok   %s" % name)
	else:
		_failures.append(name)
		print("   FAIL %s  %s" % [name, detail])


func _run() -> void:
	print("=== vram estimate ===\n")

	# Anchored to models actually measured on this card. A 7B Q4 is ~4.5GB and
	# a pair of them does NOT fit in 8GB; that eviction is measured behaviour,
	# not a guess (docs/BENCHMARK_8GB.md).
	var q4_7b := V.estimate_gb(7.0, "Q4_K_M")
	_check("a 7B Q4 lands between 4 and 5 GB", q4_7b > 4.0 and q4_7b < 5.0,
		"got %.2f" % q4_7b)
	_check("two 7B Q4 do NOT fit the default budget",
		q4_7b * 2.0 > V.DEFAULT_BUDGET_GB, "2x%.2f fits %.1f" % [q4_7b, V.DEFAULT_BUDGET_GB])

	var small := V.estimate_gb(1.6, "Q4_K_M") + V.estimate_gb(3.0, "Q4_K_M")
	_check("a 1.6B + 3B pair DOES fit (measured co-resident at 0.05s/turn)",
		small <= V.DEFAULT_BUDGET_GB, "got %.2f vs %.1f" % [small, V.DEFAULT_BUDGET_GB])

	# Monotonic in both arguments, or the ordering of candidates is meaningless.
	_check("bigger models estimate larger",
		V.estimate_gb(7.0, "Q4_K_M") > V.estimate_gb(3.0, "Q4_K_M"))
	_check("heavier quantisation estimates larger",
		V.estimate_gb(7.0, "F16") > V.estimate_gb(7.0, "Q4_K_M"))
	_check("Q8 is heavier than Q4, lighter than F16",
		V.estimate_gb(7.0, "Q8_0") > V.estimate_gb(7.0, "Q4_K_M")
		and V.estimate_gb(7.0, "Q8_0") < V.estimate_gb(7.0, "F16"))
	_check("Q2 is the lightest quantisation in the table",
		V.bytes_per_weight("Q2_K") < V.bytes_per_weight("Q3_K_M"))

	# F16 must be recognised as heavy: treating it as Q4 would let a 7B F16
	# (~15GB) look like it fits, which is the overcommit this guards against.
	_check("a 7B F16 is refused by the default budget",
		V.estimate_gb(7.0, "F16") > V.DEFAULT_BUDGET_GB,
		"got %.2f" % V.estimate_gb(7.0, "F16"))

	# Unknown size must never be planned around.
	_check("unknown parameter count is UNKNOWN, not 0",
		V.is_unknown(V.estimate_gb(0.0, "Q4_K_M")),
		"got %.2f" % V.estimate_gb(0.0, "Q4_K_M"))
	_check("a negative parameter count is also UNKNOWN",
		V.is_unknown(V.estimate_gb(-3.0, "Q4_K_M")))
	_check("no budget accepts an unknown model",
		V.estimate_gb(0.0, "") > 100.0)

	# An unrecognised quantisation must fall back, not return zero — a zero
	# would make every strange model look free and fit infinitely many.
	var weird := V.estimate_gb(3.0, "SOME_NEW_FORMAT")
	_check("an unrecognised quantisation still costs something",
		weird > 1.0 and not V.is_unknown(weird), "got %.2f" % weird)
	_check("an empty quantisation string still costs something",
		V.estimate_gb(3.0, "") > 1.0)

	_check("quantisation matching is case-insensitive",
		is_equal_approx(V.bytes_per_weight("q4_k_m"), V.bytes_per_weight("Q4_K_M")))

	# Overhead is per-model, so N models cost N allowances.
	_check("each resident model carries its own overhead",
		V.total_gb([V.estimate_gb(1.0, "Q4_K_M"), V.estimate_gb(1.0, "Q4_K_M")])
		> V.estimate_gb(2.0, "Q4_K_M"),
		"two 1B models should cost more than one 2B")

	_check("total of nothing is nothing", is_equal_approx(V.total_gb([]), 0.0))

	# --- co-residency planning ------------------------------------------
	# The case the old per-model share rule got wrong: budget/3 = 2.0 would
	# have refused the 2.8 entirely, even though 2.8+1.5+1.5 = 5.8 fits.
	var plan := V.plan_fit([2.8, 1.5, 1.5, 1.5], 6.0, 5)
	_check("a model larger than budget/k is still reachable",
		plan.size() == 3 and plan.has(0),
		"got %s" % str(plan))

	_check("planning prefers MORE architectures over better-ranked ones",
		V.plan_fit([5.5, 1.5, 1.5, 1.5], 6.0, 5).size() == 3,
		"got %s" % str(V.plan_fit([5.5, 1.5, 1.5, 1.5], 6.0, 5)))

	_check("the chosen set actually fits the budget",
		_total([2.8, 1.5, 1.5, 1.5], V.plan_fit([2.8, 1.5, 1.5, 1.5], 6.0, 5)) <= 6.0)

	_check("it never returns more than asked for",
		V.plan_fit([1.0, 1.0, 1.0, 1.0, 1.0, 1.0], 100.0, 3).size() == 3)

	_check("when nothing pairs up it returns the one model that fits",
		V.plan_fit([5.5, 5.5, 5.5], 6.0, 5) == [0],
		"got %s" % str(V.plan_fit([5.5, 5.5, 5.5], 6.0, 5)))

	_check("an impossible budget returns nothing at all",
		V.plan_fit([9.0, 9.0], 6.0, 5).is_empty())

	_check("unknown sizes are never planned around",
		not V.plan_fit([V.UNKNOWN, 1.5, 1.5], 6.0, 5).has(0),
		"an unsized model must not enter a co-residency plan")

	_check("an empty catalogue plans nothing",
		V.plan_fit([], 6.0, 5).is_empty())

	# --- budget from the card actually present --------------------------
	_check("an 8GB card plans against about 6GB",
		absf(V.budget_from_gpu(8151) - 5.97) < 0.1,
		"got %.2f" % V.budget_from_gpu(8151))

	# 24GB * 0.75 = 18.0, which is exactly 3x the 8GB default -- the first
	# version of this check asserted "> 3x" and failed on the tie.
	_check("a 24GB card plans against three times the 8GB default",
		absf(V.budget_from_gpu(24576) - 18.0) < 0.01,
		"got %.2f" % V.budget_from_gpu(24576))

	_check("a 6GB card plans against less than the 8GB default",
		V.budget_from_gpu(6144) < V.DEFAULT_BUDGET_GB,
		"got %.2f" % V.budget_from_gpu(6144))

	_check("a tiny card still gets a usable floor, not zero",
		V.budget_from_gpu(2048) >= V.MIN_BUDGET_GB)

	_check("an enormous card is capped rather than unbounded",
		V.budget_from_gpu(196608) <= V.MAX_BUDGET_GB)

	_check("an unknown card falls back to the documented default",
		is_equal_approx(V.budget_from_gpu(0), V.DEFAULT_BUDGET_GB))

	_check("a negative reading is treated as unknown",
		is_equal_approx(V.budget_from_gpu(-1), V.DEFAULT_BUDGET_GB))

	_check("nvidia-smi output parses",
		V.parse_gpu_memory_mib("8151 MiB") == 8151,
		"got %d" % V.parse_gpu_memory_mib("8151 MiB"))

	_check("a bare number parses",
		V.parse_gpu_memory_mib("24576") == 24576)

	_check("only the first GPU is taken",
		V.parse_gpu_memory_mib("8151 MiB
24576 MiB") == 8151)

	_check("junk output is unknown, not zero-budget",
		V.parse_gpu_memory_mib("no devices found") == 0)

	_check("empty output is unknown",
		V.parse_gpu_memory_mib("") == 0)

	_report()


func _total(costs: Array, idx: Array) -> float:
	var t := 0.0
	for i in idx:
		t += float(costs[i])
	return t


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("VRAM OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
