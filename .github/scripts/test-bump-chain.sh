#!/usr/bin/env bash
# Tests for bump-chain.sh with a fake gh, fake gate/watchdog scripts and a throwaway git
# repo. Run: bash .github/scripts/test-bump-chain.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$tmp/bin"
cp "$here/fake-gh.sh" "$tmp/bin/gh"
chmod +x "$tmp/bin/gh"

# The chain script runs git fetch/switch against origin/main
git init -q --bare -b main "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/repo" 2>/dev/null
( cd "$tmp/repo" && git config user.name t && git config user.email t@example.test \
  && echo x > f && git add f && git commit -q -m init && git branch -q -M main && git push -q origin main ) 2>/dev/null

# Fake gate: each call pops one action from $GATE_PLAN (the last one repeats)
cat > "$tmp/fake-gate.sh" <<'EOF'
#!/usr/bin/env bash
echo gate >> "$EVENTS"
line=$(head -n 1 "$GATE_PLAN"); [ "$(wc -l < "$GATE_PLAN")" -gt 1 ] && sed -i 1d "$GATE_PLAN"
case $line in
    merge) echo MERGED > "$GH_STATE_FILE" ;;
    close) echo CLOSED > "$GH_STATE_FILE" ;;
    fail)  printf '{"comments":[{"body":"x <!-- bump-gate:fail:headsha1 -->"}]}' > "$GH_COMMENTS" ;;
esac
EOF
# Fake watchdog: prints the same verdict line the real one does
cat > "$tmp/fake-watchdog.sh" <<'EOF'
#!/usr/bin/env bash
echo watchdog >> "$EVENTS"
line=$(head -n 1 "$WATCHDOG_PLAN"); [ "$(wc -l < "$WATCHDOG_PLAN")" -gt 1 ] && sed -i 1d "$WATCHDOG_PLAN"
echo "mergesh: watchdog verdict $line (changed: facetimehd)"
EOF
chmod +x "$tmp/fake-gate.sh" "$tmp/fake-watchdog.sh"

run() { # run <label> <gate plan> <watchdog plan> [env...]; sets $rc, $tmp/calls, $tmp/events
    local label=$1; printf '%b' "$2" > "$tmp/gate_plan"; printf '%b' "$3" > "$tmp/wd_plan"; shift 3
    : > "$tmp/calls"; : > "$tmp/events"
    echo OPEN > "$tmp/state"; printf '{"comments":[]}' > "$tmp/comments.json"
    set +e
    ( cd "$tmp/repo" && env PATH="$tmp/bin:$PATH" GH_CALLS="$tmp/calls" EVENTS="$tmp/events" \
        GH_STATE_FILE="$tmp/state" GH_COMMENTS="$tmp/comments.json" \
        GATE_PLAN="$tmp/gate_plan" WATCHDOG_PLAN="$tmp/wd_plan" \
        GATE_SCRIPT="$tmp/fake-gate.sh" WATCHDOG_SCRIPT="$tmp/fake-watchdog.sh" \
        REPO=o/r OWNER=mulderje RUN_URL=https://example.test/run POLL_SECONDS=0 MAX_POLLS=4 "$@" \
        bash "$here/bump-chain.sh" 15 ) > "$tmp/out" 2>&1
    rc=$?
    set -e
}
calls() { cat "$tmp/calls"; }
count() { grep -c "^$1\$" "$tmp/events" || true; }

# (a) builds pending, then merged; main builds pending, then ok: success and final comment
run "happy path" 'wait\nmerge\n' 'pending\nok\n'
[ "$rc" = 0 ] || { cat "$tmp/out"; fail "happy path: exit $rc"; }
[ "$(count gate)" = 2 ] && [ "$(count watchdog)" = 2 ] || fail "happy path: wrong call counts"
calls | grep -qF 'the Packit builds on main passed' || fail "happy path: no success comment"

# (b) the PR builds failed: stop, never look at main
run "builds failed" 'fail\n' 'ok\n'
[ "$rc" != 0 ] || fail "builds failed: exit 0"
[ "$(count watchdog)" = 0 ] || fail "builds failed: watchdog ran"
[ "$(count gate)" = 1 ] || fail "builds failed: kept polling after the failure was reported"
! calls | grep -qF 'Gave up waiting' || fail "builds failed: fell through to the timeout"
! calls | grep -qF 'passed. Workflow' || fail "builds failed: success comment posted"

# (c) the PR was closed by someone
run "closed" 'close\n' 'ok\n'
[ "$rc" != 0 ] || fail "closed: exit 0"
[ "$(count watchdog)" = 0 ] || fail "closed: watchdog ran"

# (d) the PR builds never finish
run "builds time out" 'wait\n' 'ok\n'
[ "$rc" != 0 ] || fail "builds time out: exit 0"
calls | grep -qF 'Gave up waiting for the Packit PR builds' || fail "builds time out: no comment"

# (e) merged, then the main builds fail for a changed package: red run, no success comment
run "main failed" 'merge\n' 'pending\nrevert\n'
[ "$rc" != 0 ] || fail "main failed: exit 0"
! calls | grep -qF 'passed. Workflow' || fail "main failed: success comment posted"
[ "$(count watchdog)" = 2 ] || fail "main failed: kept polling after the watchdog reported"
! calls | grep -qF 'did not finish in time' || fail "main failed: fell through to the timeout"

# (f) failures only in unchanged packages are reported by the watchdog but still red
run "main comment" 'merge\n' 'comment\n'
[ "$rc" != 0 ] || fail "main comment: exit 0"
[ "$(count watchdog)" = 1 ] || fail "main comment: kept polling after the watchdog reported"

# (g) merged, but the main builds never finish
run "main time out" 'merge\n' 'pending\n'
[ "$rc" != 0 ] || fail "main time out: exit 0"
calls | grep -qF 'did not finish in time' || fail "main time out: no comment"

# (h) pipeline test: the gate closed the PR with the passed marker; success, main never checked
run "smoke" 'close\n' 'ok\n'
printf '{"comments":[{"body":"x <!-- bump-gate:smoke-passed:headsha1 -->"}]}' > "$tmp/comments.json"
echo CLOSED > "$tmp/state"
set +e
( cd "$tmp/repo" && env PATH="$tmp/bin:$PATH" GH_CALLS="$tmp/calls" EVENTS="$tmp/events" \
    GH_STATE_FILE="$tmp/state" GH_COMMENTS="$tmp/comments.json" GATE_PLAN="$tmp/gate_plan" \
    WATCHDOG_PLAN="$tmp/wd_plan" GATE_SCRIPT="$tmp/fake-gate.sh" WATCHDOG_SCRIPT="$tmp/fake-watchdog.sh" \
    REPO=o/r OWNER=mulderje RUN_URL=x POLL_SECONDS=0 MAX_POLLS=4 bash "$here/bump-chain.sh" 15 ) > "$tmp/out" 2>&1
rc=$?
set -e
[ "$rc" = 0 ] || { cat "$tmp/out"; fail "smoke: exit $rc"; }
[ "$(count watchdog)" = 0 ] || fail "smoke: watchdog ran"

echo PASS
