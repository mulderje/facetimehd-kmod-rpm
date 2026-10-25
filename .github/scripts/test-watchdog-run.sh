#!/usr/bin/env bash
# Tests for watchdog-run.sh with a fake gh and a throwaway git repo.
# Run: bash .github/scripts/test-watchdog-run.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$tmp/bin"
cp "$here/fake-gh.sh" "$tmp/bin/gh"
chmod +x "$tmp/bin/gh"

# A bare origin and a clone with: initial commit, then a "driver bump" that touches
# facetimehd/ and facetimehd-kmod/ only (the shape of a squash-merged bump PR).
git init -q --bare -b main "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/repo" 2>/dev/null
cd "$tmp/repo"
git config user.name test
git config user.email test@example.test
mkdir facetimehd facetimehd-kmod facetimehd-firmware
for p in facetimehd facetimehd-kmod facetimehd-firmware; do echo "v1" > "$p/$p.spec"; done
git add -A && git commit -q -m "initial" && git branch -q -M main && git push -q origin main
echo "v2" > facetimehd/facetimehd.spec; echo "v2" > facetimehd-kmod/facetimehd-kmod.spec
git add -A && git commit -q -m "Update facetimehd to 0.7.3 (#30)" && git push -q origin main
bump=$(git rev-parse HEAD)

builds() { # builds <failing-package-or-none>
    jq -n --arg bad "$1" '
      ["fedora-43-x86_64","fedora-rawhide-x86_64"] as $c
      | ["facetimehd","facetimehd-firmware","facetimehd-kmod"] as $p
      | {check_runs: [ $c[] as $ch | $p[] as $pk
          | {name:"rpm-build:main:\($ch):\($pk)", status:"completed",
             conclusion:(if $pk == $bad then "failure" else "success" end),
             html_url:"https://example.test/\($ch)/\($pk)", app:{slug:"packit-as-a-service"}} ]}'
}
bump_pr='[{"number":30,"merged_at":"2026-10-25T00:00:00Z","user":{"login":"github-actions[bot]"},"head":{"ref":"bump/facetimehd"}}]'

run() { # run <label> [env assignments...]
    : > "$tmp/calls"
    ( cd "$tmp/repo" && git switch -q --detach origin/main \
      && env PATH="$tmp/bin:$PATH" GH_CALLS="$tmp/calls" GH_PULLS="$tmp/pulls.json" \
        GH_CHECKS="$tmp/checks.json" GH_COMMENTS="$tmp/comments.json" \
        REPO=o/r OWNER=mulderje RUN_URL=https://example.test/run "${@:2}" \
        bash "$here/watchdog-run.sh" ) > "$tmp/out" 2>&1 \
        || { cat "$tmp/out"; fail "$1: watchdog-run.sh exited non-zero"; }
}
calls() { cat "$tmp/calls"; }
printf '%s' "$bump_pr" > "$tmp/pulls.json"
printf '%s' '{"comments":[]}' > "$tmp/comments.json"
revert_branch="revert/${bump:0:7}"

# (a) everything built: nothing happens
builds none > "$tmp/checks.json"
run "all green" SHA="$bump"
! calls | grep -qE 'pr (create|comment)' || fail "all green: acted"

# (b) firmware failed after a driver bump: comment only, no revert branch
builds facetimehd-firmware > "$tmp/checks.json"
run "firmware failure" SHA="$bump"
calls | grep -qF 'did not change' || fail "firmware failure: no comment"
! calls | grep -q 'pr create' || fail "firmware failure: opened a revert"
! git ls-remote --exit-code --heads "$tmp/origin.git" "$revert_branch" >/dev/null 2>&1 || fail "firmware failure: pushed a revert branch"

# (c) the kmod failed: revert branch pushed, revert PR opened, original PR told
builds facetimehd-kmod > "$tmp/checks.json"
run "kmod failure" SHA="$bump"
git ls-remote --exit-code --heads "$tmp/origin.git" "$revert_branch" >/dev/null || fail "kmod failure: revert branch missing"
calls | grep -qF "pr create --base main --head $revert_branch" || { calls; fail "kmod failure: no revert PR"; }
calls | grep -qF 'Signed-off-by: Jon Mulder' || fail "kmod failure: revert PR body lacks sign-off"
calls | grep -qF 'is being reverted in https://example.test/pull/99' || fail "kmod failure: original PR not told"
calls | grep -qF 'pr edit https://example.test/pull/99 --add-reviewer mulderje' || fail "kmod failure: review not requested"
[ "$(git -C "$tmp/origin.git" show "$revert_branch:facetimehd/facetimehd.spec")" = "v1" ] || fail "kmod failure: revert did not restore v1"

# (d) already reported (marker comment): no second revert PR. The revert branch is removed
# first (as after a merged revert) so only the marker can stop a repeat.
git -C "$tmp/origin.git" branch -q -D "$revert_branch"
printf '%s' "{\"comments\":[{\"body\":\"x <!-- watchdog:$bump -->\"}]}" > "$tmp/comments.json"
run "already reported" SHA="$bump"
! calls | grep -qE 'pr (create|comment)' || fail "already reported: acted again"
! git ls-remote --exit-code --heads "$tmp/origin.git" "$revert_branch" >/dev/null 2>&1 || fail "already reported: pushed a revert branch"
printf '%s' '{"comments":[]}' > "$tmp/comments.json"

# (e) not from a bump PR (human commit): ignored even though the build failed
printf '%s' '[]' > "$tmp/pulls.json"
run "not a bump" SHA="$bump"
! calls | grep -qE 'pr (create|comment)' || fail "not a bump: acted"
printf '%s' "$bump_pr" > "$tmp/pulls.json"

# (f) sweep mode (no SHA) finds the bump among the latest commits on main
run "sweep"
git ls-remote --exit-code --heads "$tmp/origin.git" "$revert_branch" >/dev/null || fail "sweep: revert branch missing"

echo PASS
