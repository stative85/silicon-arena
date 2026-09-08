"""Generate the Arena roster from FROZEN membership, offline. NO_CONTACT.

    python tools/build_canonical_roster.py --check     verify the on-disk roster
    python tools/build_canonical_roster.py --write     regenerate it
    python tools/build_canonical_roster.py --selftest  qualify this tooth

WHY THIS EXISTS ALONGSIDE tools/build_roster.gd

`build_roster.gd` DISCOVERS a roster: it queries LM Studio for available models,
scores them, and sends probe inference to see which ones behave. That is the
right tool for "what can this machine field?" and it is CONTACT_REQUIRED by
nature.

A FROZEN roster needs no discovery. Membership is a decision, already made, and
re-deriving it from whatever happens to be loaded is how a roster silently
changes between runs. So this generator reads the decision and writes the file,
touching nothing:

    config/arena-species.v1.json     MEMBERSHIP -- who is in the Arena
              |
              v
    build_canonical_roster.py  --->  config/arena-roster.v1.json
              ^
              |
    config/arena-names.v1.json       DECORATION -- what humans see

THE DIRECTION THAT MATTERS

Names have no vote. A species with no display name is still a member and renders
as its raw model_id. A display name for something not in the species file adds
nobody. Both directions are proven by sabotage in --selftest, because "the names
file is only decoration" is exactly the kind of claim that stays true until
someone finds it convenient.

FIVE SPECIES, ONE INSTANCE EACH

The Arena thesis is heterogeneous local agents, so the default roster is five
genuinely different architectures with one incarnation apiece. Duplicate
instances are deliberately NOT the default: they are a future experimental
manipulation (5 distinct vs 3+duplicates vs 1x5), and mixing that into the
baseline would confound heterogeneity with "merely having several actors".

PERSONA IS BOUND TO THE SLOT, NOT THE SPECIES -- see PERSONA_CONFOUND below.
"""

import argparse
import collections
import importlib.util
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPECIES_PATH = os.path.join(REPO, "config", "arena-species.v1.json")
ROSTER_PATH = os.path.join(REPO, "config", "arena-roster.v1.json")

_spec = importlib.util.spec_from_file_location(
    "arena_names", os.path.join(REPO, "tools", "arena_names.py"))
NAMES = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(NAMES)

ENDPOINT = "http://127.0.0.1:1234/v1"

# Personas are bound to the AGENT SLOT (agent-01..agent-05), never to a species.
#
# PERSONA_CONFOUND -- stated because it is not fixable by ordering: with one
# instance per species and one persona per slot, persona and species are
# PERFECTLY CONFOUNDED. Any difference between VANTA and BRINE is a difference
# between (lfm2.5 + systems engineer) and (danube2 + historian), and no single
# run separates them.
#
# The consequence depends on WHAT THE CLAIM SAYS, not on how the run is
# configured. Do not over-correct by rotating personas everywhere: rotation
# changes prompt identity, social framing and contention, so it is ANOTHER
# TREATMENT, not a neutralisation.
#
#   SYSTEM-LEVEL ECOLOGY CLAIM -- "this five-agent system, with these models
#   and these frozen personas, produced X" -> frozen assignment is ALLOWED.
#   The claim attaches to the whole configured system and attributes nothing
#   to a model alone.
#
#   SPECIES-ATTRIBUTION CLAIM -- "VANTA behaves differently BECAUSE it is
#   LFM2.5" -> persona must be controlled experimentally: rotate, Latin
#   square, neutralise, or otherwise PREREGISTER it.
#
# The trap is drift between the two. A run is designed as system-level, the
# results are interesting, and the write-up reaches for the species explanation
# because it is the better sentence. The moment a sentence attributes behaviour
# to a MODEL rather than to the SYSTEM, it has switched claim types and needs
# the control it never had. See docs/ARENA_IDENTITY_LAYERS.md.
PERSONAS = [
    "a systems engineer who wants mechanisms and refuses abstraction",
    "a moral philosopher who tests every claim against a hard edge case",
    "a sceptic who assumes the other speakers are smuggling in assumptions",
    "a pragmatist who only cares what would actually change in practice",
    "a historian who answers new claims with how the old ones failed",
]
COLORS = ["#c471ed", "#3db1ff", "#00d2ff", "#5ad78c", "#ff6b6b"]


def load_species(path=None):
    with open(path or SPECIES_PATH, encoding="utf-8") as f:
        doc = json.load(f)
    if int(doc.get("schema_version", 0)) != 1:
        raise ValueError("arena-species: unsupported schema_version %r"
                         % doc.get("schema_version"))
    per = int(doc.get("instances_per_species", 0))
    if per != 1:
        # Multiplicity is a deliberate experimental manipulation. It does not
        # arrive by editing a number in the default roster config.
        raise ValueError(
            "arena-species: instances_per_species=%r. The default roster is "
            "one instance per species; duplicates are an experimental factor "
            "and need their own preregistration, not a config edit." % per)
    rows = doc.get("species") or []
    if not rows:
        raise ValueError("arena-species: no species declared")
    ids = [r.get("model_id") for r in rows]
    sp = [r.get("species_id") for r in rows]
    for r in rows:
        for k in ("model_id", "species_id"):
            if not str(r.get(k, "")).strip():
                raise ValueError("arena-species: row missing %s: %r" % (k, r))
        if ":" in str(r["model_id"]):
            raise ValueError(
                "arena-species: %r carries an instance suffix. Membership is "
                "declared per SPECIES; instances are a runtime fact."
                % r["model_id"])
    for label, seq in (("model_id", ids), ("species_id", sp)):
        dup = [k for k, v in collections.Counter(seq).items() if v > 1]
        if dup:
            raise ValueError("arena-species: duplicate %s %r" % (label, dup))
    return rows


def build(species=None, names=None):
    """Pure function: membership + decoration -> roster document."""
    species = load_species() if species is None else species
    names = NAMES.load() if names is None else names

    agents = []
    for i, s in enumerate(species):
        # display_for returns None for an unnamed species. label() then falls
        # back to the raw model_id: ugly, true, and still a member.
        agents.append({
            "agent_id": "agent-%02d" % (i + 1),
            "color": COLORS[i % len(COLORS)],
            "display_name": NAMES.label(s["model_id"], names),
            "model_key": s["model_id"],
            "persona": PERSONAS[i % len(PERSONAS)],
            "runtime_id": "runtime-01",
            "species_id": s["species_id"],
        })

    first = species[0]
    return {
        "agents": agents,
        "generated_by": "tools/build_canonical_roster.py",
        "membership_source": "config/arena-species.v1.json",
        "names_source": "config/arena-names.v1.json (display only)",
        "runtimes": [{
            "display_name": NAMES.label(first["model_id"], names),
            "endpoint": ENDPOINT,
            "inference": {
                "max_tokens": 110,
                "notes": "generated defaults; tune per model family",
                "temperature": 0.8,
            },
            "model_key": first["model_id"],
            "params_b": first.get("params_b"),
            "quantization": "",
            "runtime_id": "runtime-01",
        }],
        "version": 1,
    }


def render(doc):
    return json.dumps(doc, indent="\t", sort_keys=True) + "\n"


def write():
    text = render(build())
    with open(ROSTER_PATH, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("wrote config/arena-roster.v1.json (%d agents)"
          % len(json.loads(text)["agents"]))
    return 0


def check():
    """Fail closed: the on-disk roster must be what the frozen inputs produce."""
    want = render(build())
    try:
        with open(ROSTER_PATH, encoding="utf-8") as f:
            got = f.read()
    except OSError as e:
        print("REFUSED -- cannot read the roster: %s" % e)
        return 1
    if got != want:
        print("REFUSED -- config/arena-roster.v1.json does not match its")
        print("frozen inputs. It was hand-edited, or the inputs changed and it")
        print("was not regenerated. Run --write, do not edit the roster.")
        return 1
    print("roster matches config/arena-species.v1.json + arena-names.v1.json")
    return 0


# --- selftest --------------------------------------------------------------

_n = _f = 0


def ck(lbl, cond, detail=""):
    global _n, _f
    _n += 1
    if cond:
        print("  ok   %s" % lbl)
    else:
        _f += 1
        print("  FAIL %s %s" % (lbl, detail))


def selftest():
    import copy
    print("=== canonical roster: membership decides, names decorate ===")
    species = load_species()
    names = NAMES.load()
    doc = build(species, names)

    ck("five species declared", len(species) == 5, str(len(species)))
    ck("five agents generated", len(doc["agents"]) == 5)
    ck("five DISTINCT species_ids",
       len({a["species_id"] for a in doc["agents"]}) == 5)
    ck("one instance each: no model_key repeats",
       len({a["model_key"] for a in doc["agents"]}) == 5)
    ck("no agent carries an instance suffix",
       all(":" not in a["model_key"] for a in doc["agents"]))
    ck("the roster reads VANTA/KESTREL/GEMMATRON/OZONIOUS/BRINE",
       [a["display_name"] for a in doc["agents"]]
       == ["VANTA", "KESTREL", "GEMMATRON", "OZONIOUS", "BRINE"],
       str([a["display_name"] for a in doc["agents"]]))

    print("\n[identity survives decoration]")
    ck("every model_key is a canonical id, not a pretty name",
       all(a["model_key"] == s["model_id"]
           for a, s in zip(doc["agents"], species)))
    ck("runtimes[0].model_key is canonical too",
       doc["runtimes"][0]["model_key"] == species[0]["model_id"])
    # Reuse the contamination auditor on the generated document itself.
    tmp = os.path.join(REPO, "docs", "night", "_roster_probe.json")
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(doc, f)
        ck("generated roster passes the contamination audit",
           NAMES.audit_paths([tmp], names) == [])
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)

    print("\n[sabotage: can the NAMES file change who is in the Arena?]")
    # SABOTAGE 1 -- delete a name. The species must remain a member.
    fewer = [r for r in copy.deepcopy(names) if r["display_name"] != "GEMMATRON"]
    ck("SABOTAGE 1 APPLIED (GEMMATRON removed from names)",
       len(fewer) == len(names) - 1)
    d1 = build(species, fewer)
    ck("SABOTAGE 1 BITES: the species is STILL a member",
       len(d1["agents"]) == 5 and any(a["model_key"] == "qwen3.5-2b"
                                      for a in d1["agents"]))
    ck("...and renders as its raw model_id, not a guess",
       [a for a in d1["agents"] if a["model_key"] == "qwen3.5-2b"
        ][0]["display_name"] == "qwen3.5-2b")
    ck("...and its species_id is untouched",
       [a for a in d1["agents"] if a["model_key"] == "qwen3.5-2b"
        ][0]["species_id"] == "qwen35")

    # SABOTAGE 2 -- add a name for a non-member. It must add nobody.
    more = copy.deepcopy(names) + [{"display_name": "INTERLOPER",
                                    "model_id": "gpt-2-xl",
                                    "species_id": "gpt2"}]
    ck("SABOTAGE 2 APPLIED (INTERLOPER added to names)",
       len(more) == len(names) + 1)
    d2 = build(species, more)
    ck("SABOTAGE 2 BITES: the roster is still 5 agents",
       len(d2["agents"]) == 5, str(len(d2["agents"])))
    ck("...and INTERLOPER is nowhere in it",
       "INTERLOPER" not in json.dumps(d2))

    print("\n[sabotage: can multiplicity arrive by editing a number?]")
    bad = {"schema_version": 1, "instances_per_species": 3,
           "species": copy.deepcopy(species)}
    tmp = os.path.join(REPO, "docs", "night", "_species_bad.json")
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(bad, f)
        ck("SABOTAGE 3 APPLIED (instances_per_species=3 written)",
           os.path.exists(tmp))
        try:
            load_species(tmp)
            ck("SABOTAGE 3 BITES: duplicates refused", False, "accepted")
        except ValueError as e:
            ck("SABOTAGE 3 BITES: duplicates refused",
               "preregistration" in str(e))
        # duplicate species in the membership list
        dupd = {"schema_version": 1, "instances_per_species": 1,
                "species": copy.deepcopy(species) + [copy.deepcopy(species[2])]}
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(dupd, f)
        try:
            load_species(tmp)
            ck("a repeated species is refused", False, "accepted")
        except ValueError as e:
            ck("a repeated species is refused", "duplicate" in str(e))
        # an instance suffix in membership
        sfx = {"schema_version": 1, "instances_per_species": 1,
               "species": copy.deepcopy(species)}
        sfx["species"][2]["model_id"] = "qwen3.5-2b:2"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(sfx, f)
        try:
            load_species(tmp)
            ck("an instance suffix in membership is refused", False, "accepted")
        except ValueError as e:
            ck("an instance suffix in membership is refused",
               "instance suffix" in str(e))
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
        ck("SABOTAGE REVERTED (temp species files removed)",
           not os.path.exists(tmp))

    print("\n[determinism and the on-disk roster]")
    ck("generation is byte-deterministic",
       render(build(species, names)) == render(build(species, names)))
    ck("the on-disk roster matches its frozen inputs", check() == 0)

    print("\n[persona is bound to the slot, and the confound is declared]")
    ck("membership declares no display_name (decoration cannot hide there)",
       not any("display_name" in r
               for r in json.load(open(SPECIES_PATH,
                                       encoding="utf-8"))["species"]))
    ck("membership carries no residency or loaded flag",
       not any(k in r
               for r in json.load(open(SPECIES_PATH,
                                       encoding="utf-8"))["species"]
               for k in ("resident", "loaded", "instances", "count")))
    ck("decoration declares no membership or instance count",
       not any(k in json.load(open(os.path.join(REPO, "config",
                                                "arena-names.v1.json"),
                                   encoding="utf-8"))
               for k in ("instances_per_species", "species")))
    ck("I-5 holds: GEMMATRON:2 renders distinctly, same species_id",
       NAMES.display_for("qwen3.5-2b:2", names) == "GEMMATRON:2"
       and NAMES.species_for("qwen3.5-2b:2", names)
       == NAMES.species_for("qwen3.5-2b", names))
    ck("persona order is positional, independent of species",
       [a["persona"] for a in doc["agents"]] == PERSONAS)
    ck("PERSONA_CONFOUND is stated in this file, not left implicit",
       "PERSONA_CONFOUND" in open(__file__, encoding="utf-8").read())
    _src = open(__file__, encoding="utf-8").read()
    ck("...and states BOTH claim types, not just the confound",
       "SYSTEM-LEVEL ECOLOGY CLAIM" in _src
       and "SPECIES-ATTRIBUTION CLAIM" in _src)

    print("\nchecks %d, failures %d" % (_n, _f))
    print("CANONICAL ROSTER GREEN" if _f == 0 else "CANONICAL ROSTER RED")
    return 1 if _f else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.write:
        return write()
    if a.check:
        return check()
    print(render(build()), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
