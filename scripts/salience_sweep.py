#!/usr/bin/env python3
"""Deterministic salience sweep over every memory root.

Recomputes the salience of each project_* and strategic_* file from its
frontmatter with the formula in docs/ADVANCED.md section 3 and reports where
the written value drifted. Read-only: prints JSON, never writes to a memory
file. Applying a restamp is the job of the skill that asked, after the
operator approves it. Exit 2 on a malformed --as-of.
"""
import argparse, datetime as dt, json, os, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_index  # memory_roots, split_frontmatter, is_skipped

# Term weights in hundredths, as documented in docs/ADVANCED.md section 3.
STATUS_WEIGHT = {"\U0001F534": 30, "\U0001F7E1": 25, "\U0001F7E2": 20,
                 "\U0001F7E0": 15, "\U0001F535": 5, "❌": 0}
DECAY_PERIOD_DAYS = 30  # one decay step of the formula
# An item is cold when its score is no higher than what a 🟢 status contributes
# on its own (0.20) and it has sat idle for at least one decay period: by then
# the status emoji is the only thing keeping it warm, and the emoji is stale.
COLD_SCORE = 0.2
DRIFT = 0.05  # half of one decimal; a smaller difference is rounding, not drift
SWEEP_TYPES = ("project", "strategic")
WARM_STATUSES = ("\U0001F7E1", "\U0001F7E2")


def fail(msg):
    print(f"salience_sweep: {msg}", file=sys.stderr)
    sys.exit(2)


def parse_iso(s, what):
    try:
        return dt.date.fromisoformat(s)
    except ValueError:
        fail(f"{what} is not valid: {s!r} (expected YYYY-MM-DD)")


def compute(fm, as_of):
    """Returns (salience rounded to one decimal, days since last_touched or None).

    Arithmetic in whole hundredths, rounded half up, so that a human working
    the table in docs/ADVANCED.md by hand lands on the same number.
    """
    lt = fm.get("last_touched")
    days = (as_of - dt.date.fromisoformat(lt)).days if lt else None
    recency = 0
    if days is not None:
        recency = 30 if days < 7 else 20 if days < 14 else 10 if days < 30 else 0
    proximity = 0
    if fm.get("deadline"):
        left = (dt.date.fromisoformat(fm["deadline"]) - as_of).days
        proximity = 0 if left < -7 else 40 if left < 7 else 25 if left < 30 else 10 if left < 90 else 0
    status = fm.get("status", "").strip()
    weight = STATUS_WEIGHT.get(status[:1], 0) if status else 0
    pinned = 40 if fm.get("pinned", "").lower() == "true" else 0
    decay = (days // DECAY_PERIOD_DAYS) * 10 if days is not None else 0
    hundredths = max(0, min(100, recency + proximity + weight + pinned - decay))
    return (hundredths + 5) // 10 / 10, days


def sweep(repo, as_of):
    scores, restamps, declass, emoji, errors = [], [], [], [], []
    for mem in build_index.memory_roots(repo):
        rroot = os.path.relpath(mem, repo)
        for fn in sorted(os.listdir(mem)):
            if not fn.endswith(".md") or build_index.is_skipped(fn):
                continue
            try:
                with open(os.path.join(mem, fn), encoding="utf-8") as fh:
                    fm, _ = build_index.split_frontmatter(fh.read())
                if fm.get("type") not in SWEEP_TYPES:
                    continue
                computed, days = compute(fm, as_of)
            except (UnicodeDecodeError, ValueError, OSError) as e:
                # One bad file must not kill the sweep for the whole corpus: a date
                # that doesn't parse (ValueError), content that isn't valid UTF-8
                # (UnicodeDecodeError, itself a ValueError subclass, named here for
                # clarity), or a file that is unreadable or vanishes mid-run
                # (OSError) all land as one entry in `errors` and the loop moves on.
                errors.append({"file": fn, "root": rroot, "error": str(e)})
                continue
            written = None
            if "salience" in fm:
                try:
                    written = float(fm["salience"])
                except ValueError:
                    written = 0.0
            item = {"file": fn, "root": rroot, "computed": computed, "written": written,
                    "days_idle": days}
            scores.append(item)
            if written is not None and abs(computed - written) >= DRIFT:
                restamps.append(item)
                if computed < written:
                    declass.append(item)
            status = fm.get("status", "").strip()[:1]
            if status in WARM_STATUSES and computed <= COLD_SCORE \
                    and days is not None and days >= DECAY_PERIOD_DAYS:
                emoji.append({"file": fn, "root": rroot, "status": status, "computed": computed,
                              "days_idle": days,
                              "hint": f"{status} but idle for {days} days: consider 🟠, 🔵, or the archive"})
    return {"as_of": as_of.isoformat(), "scores": scores, "restamps": restamps,
            "declass_candidates": declass, "emoji_suggestions": emoji, "errors": errors}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", default=None)
    ap.add_argument("--as-of", dest="as_of", default=None)
    args = ap.parse_args()
    repo = args.repo
    if not repo:
        repo = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                              capture_output=True, text=True).stdout.strip()
    if not repo or not build_index.memory_roots(repo):
        fail("repo/memory not found (use --repo)")
    as_of = parse_iso(args.as_of, "--as-of") if args.as_of else dt.date.today()
    print(json.dumps(sweep(repo, as_of), ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
