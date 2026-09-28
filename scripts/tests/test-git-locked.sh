#!/usr/bin/env bash
# Tests for scripts/git-locked in a throwaway repository.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WRAPPER="$ROOT/scripts/git-locked"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" && git init -q -b main .
LOCK=".git/brain-git.lock"
fail=0

# 1. A plain command runs and the lock is gone afterwards.
"$WRAPPER" true || { echo "FAIL: plain command"; fail=1; }
[ -d "$LOCK" ] && { echo "FAIL: lock not released"; fail=1; }

# 2. The wrapped command's exit code passes through.
set +e; "$WRAPPER" bash -c 'exit 41'; rc=$?; set -e
[ "$rc" = 41 ] || { echo "FAIL: exit code not passed through (rc=$rc)"; fail=1; }

# 3. Serialization: A holds the lock for 3s, B must wait for A.
"$WRAPPER" bash -c 'sleep 3; echo A > order.txt' &
sleep 0.5
"$WRAPPER" bash -c 'echo B >> order.txt'
wait
[ "$(cat order.txt)" = "$(printf 'A\nB')" ] || { echo "FAIL: serialization (order=$(tr '\n' ' ' < order.txt))"; fail=1; }

# 4. Stale lock (dead pid, old timestamp, no integration in progress): broken.
mkdir "$LOCK"; echo "999999 100" > "$LOCK/owner"
GIT_LOCKED_STALE_SECS=1 "$WRAPPER" true || { echo "FAIL: stale lock not broken"; fail=1; }

# 5. Live lock (this very process owns it): the waiter gives up with 75.
mkdir "$LOCK"; echo "$$ $(date +%s)" > "$LOCK/owner"
set +e; GIT_LOCKED_MAX_TRIES=2 "$WRAPPER" true; rc=$?; set -e
[ "$rc" = 75 ] || { echo "FAIL: live lock not respected (rc=$rc)"; fail=1; }
rm -rf "$LOCK"

# 6. Lock with a rebase in progress: never broken, even with a dead owner.
mkdir "$LOCK" .git/rebase-merge; echo "999999 100" > "$LOCK/owner"
set +e; GIT_LOCKED_STALE_SECS=1 GIT_LOCKED_MAX_TRIES=2 "$WRAPPER" true; rc=$?; set -e
[ "$rc" = 75 ] || { echo "FAIL: lock broken during a rebase (rc=$rc)"; fail=1; }
rm -rf "$LOCK" .git/rebase-merge

# 7. Dead owner but a recent timestamp: not stale yet, not broken.
mkdir "$LOCK"; echo "999999 $(date +%s)" > "$LOCK/owner"
set +e; GIT_LOCKED_MAX_TRIES=2 "$WRAPPER" true; rc=$?; set -e
[ "$rc" = 75 ] || { echo "FAIL: recent lock with dead owner was broken (rc=$rc)"; fail=1; }
rm -rf "$LOCK"

# 8. Ten waiters discover the same stale lock at once: exactly one breaks and
#    acquires it at a time, so a non-atomic read-modify-write on a counter
#    still ends at the exact count.
mkdir "$LOCK"; echo "999999 100" > "$LOCK/owner"
echo 0 > counter
N=10
for i in $(seq 1 $N); do
  GIT_LOCKED_STALE_SECS=1 GIT_LOCKED_MAX_TRIES=120 "$WRAPPER" bash -c \
    'c=$(cat counter); sleep 0.05; echo $((c+1)) > counter' &
done
wait
got="$(cat counter)"
[ "$got" = "$N" ] || { echo "FAIL: double acquisition on a stale lock (counter=$got, expected $N)"; fail=1; }
rm -f counter; rm -rf "$LOCK" 2>/dev/null

[ "$fail" = 0 ] && echo "OK: git-locked" || exit 1
