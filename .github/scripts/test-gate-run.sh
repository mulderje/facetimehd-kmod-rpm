#!/usr/bin/env bash
# Tests for gate-run.sh against a fake gh. Run: bash .github/scripts/test-gate-run.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$tmp/bin"
cp "$here/fake-gh.sh" "$tmp/bin/gh"
chmod +x "$tmp/bin/gh"

# 12 Packit PR builds (4 Fedora targets x 3 packages) as the GitHub API returns them
checks_json=$(jq -n '
  ["fedora-43-x86_64","fedora-44-x86_64","fedora-45-x86_64","fedora-rawhide-x86_64"] as $c
  | ["facetimehd","facetimehd-firmware","facetimehd-kmod"] as $p
  | {check_runs: [ $c[] as $ch | $p[] as $pk
      | {name:"rpm-build:\($ch):\($pk)", status:"completed", conclusion:"success",
         html_url:"https://example.test/\($ch)/\($pk)", app:{slug:"packit-as-a-service"}} ]}')

pulls_json='[
 {"number":15,"state":"open","user":{"login":"github-actions[bot]"},"head":{"ref":"bump/facetimehd-firmware","sha":"aaaaaaa1"}},
 {"number":20,"state":"open","user":{"login":"mulderje"},"head":{"ref":"bump/by-a-human","sha":"bbbbbbb2"}},
 {"number":21,"state":"open","user":{"login":"github-actions[bot]"},"head":{"ref":"feature/not-a-bump","sha":"ccccccc3"}}
]'

run() { # run <label> [env assignments...]; writes calls to $tmp/calls
    : > "$tmp/calls"
    ( cd "$tmp" && env PATH="$tmp/bin:$PATH" GH_CALLS="$tmp/calls" GH_PULLS="$tmp/pulls.json" \
        GH_CHECKS="$tmp/checks.json" GH_COMMENTS="$tmp/comments.json" \
        REPO=o/r OWNER=mulderje SIGNOFF="Signed-off-by: Jon Mulder <jon.e.mulder@gmail.com>" \
        RUN_URL=https://example.test/run "${@:2}" bash "$here/gate-run.sh" ) > "$tmp/out" 2>&1 \
        || { cat "$tmp/out"; fail "$1: gate-run.sh exited non-zero"; }
}
calls() { cat "$tmp/calls"; }
printf '%s' "$pulls_json" > "$tmp/pulls.json"
printf '%s' '{"comments":[]}' > "$tmp/comments.json"

# (a) sweep, all builds green: only the bot's bump PR is merged, with sign-off
printf '%s' "$checks_json" > "$tmp/checks.json"
run "green sweep"
calls | grep -qF 'gh pr merge 15 --squash --delete-branch --subject Update facetimehd to 0.7.3 (#15)' || { calls; fail "green sweep: PR 15 not merged with subject"; }
calls | grep -qF 'Signed-off-by: Jon Mulder <jon.e.mulder@gmail.com>' || fail "green sweep: sign-off trailer missing"
! calls | grep -qE 'pr merge (20|21)' || fail "green sweep: merged a PR that is not the bot's bump"

# (b) one build failed: comment with the failing check, review requested, no merge
printf '%s' "$checks_json" | jq '.check_runs |= map(if .name=="rpm-build:fedora-44-x86_64:facetimehd-kmod" then .conclusion="failure" else . end)' > "$tmp/checks.json"
run "failed sweep"
! calls | grep -q 'pr merge' || fail "failed sweep: merged a red PR"
calls | grep -qF '@mulderje needs your review' || fail "failed sweep: owner not mentioned"
calls | grep -qF 'rpm-build:fedora-44-x86_64:facetimehd-kmod' || fail "failed sweep: failing check not listed"
calls | grep -qF 'pr edit 15 --add-reviewer mulderje' || fail "failed sweep: review not requested"

# (c) the failure was already reported: stay quiet
printf '%s' '{"comments":[{"body":"x <!-- bump-gate:fail:aaaaaaa1 -->"}]}' > "$tmp/comments.json"
run "repeat failure"
! calls | grep -qE 'pr (comment|merge|edit)' || fail "repeat failure: acted again"
printf '%s' '{"comments":[]}' > "$tmp/comments.json"

# (d) a build still running: do nothing
printf '%s' "$checks_json" | jq '.check_runs |= map(if .name=="rpm-build:fedora-45-x86_64:facetimehd" then .status="in_progress" | .conclusion=null else . end)' > "$tmp/checks.json"
run "pending sweep"
! calls | grep -qE 'pr (comment|merge|edit)' || fail "pending sweep: acted too early"

# (e) check_run mode: a commit that is not a bot bump head does nothing
printf '%s' "$checks_json" > "$tmp/checks.json"
run "check_run other sha" SHA=zzzzzzz9
! calls | grep -qE 'pr (comment|merge|edit)' || fail "check_run other sha: acted"

# (f) check_run mode: the bot PR's own head sha merges it
run "check_run own sha" SHA=aaaaaaa1
calls | grep -qF 'pr merge 15' || fail "check_run own sha: not merged"

# (g) merge fails (conflict): ask for a manual merge once, do not error out
run "merge failure" GH_MERGE_RC=1
calls | grep -qF 'the merge failed' || fail "merge failure: not reported"

# (h) another run already merged it: no second merge, no failure report
run "already merged" GH_PR_STATE=MERGED
! calls | grep -qE 'pr (merge|comment)' || fail "already merged: acted"

# (i) our merge fails because another run merged it between the two state checks
printf 'OPEN\nMERGED\n' > "$tmp/state"
run "merge race" GH_MERGE_RC=1 GH_STATE_FILE="$tmp/state"
! calls | grep -qF 'the merge failed' || fail "merge race: reported a failure for a PR that was merged"

# (j) PRs opened by the GitHub App are bot PRs too
printf '%s' '[{"number":22,"state":"open","user":{"login":"facetimehd-rpm-bot[bot]"},"head":{"ref":"bump/facetimehd","sha":"ddddddd4"}}]' > "$tmp/pulls.json"
printf '%s' "$checks_json" > "$tmp/checks.json"
printf '%s' '{"comments":[]}' > "$tmp/comments.json"
run "app pr"
calls | grep -qF 'gh pr merge 22 --squash' || { calls; fail "app pr: not merged"; }

# (k) pipeline test (SMOKE): green PR is closed with its branch deleted, never merged
run "smoke" SMOKE=true
! calls | grep -q 'pr merge' || fail "smoke: merged"
calls | grep -qF 'gh pr close 22 --delete-branch' || { calls; fail "smoke: not closed with branch deleted"; }
calls | grep -qF 'bump-gate:smoke-passed:ddddddd4' || fail "smoke: marker missing"

# (l) a ci-test label alone makes it a pipeline test, even from an event run without SMOKE
run "label smoke" GH_LABELS=ci-test
! calls | grep -q 'pr merge' || fail "label smoke: merged"
calls | grep -qF 'gh pr close 22 --delete-branch' || fail "label smoke: not closed"

echo PASS
