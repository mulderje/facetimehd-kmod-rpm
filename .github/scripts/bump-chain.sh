#!/usr/bin/env bash
# Follow one bump PR through the whole pipeline, inside the workflow run that opened it:
#   1. wait for Packit's PR builds; gate-run.sh merges the PR when they pass and comments
#      (and asks the owner for a review) when they fail;
#   2. wait for Packit's builds of the merge commit on main; watchdog-run.sh opens a revert
#      PR when a package the bump changed fails;
#   3. comment the outcome on the PR.
# The script exits non-zero whenever a human needs to look, so the run is red and GitHub
# emails the owner.
#
# Usage: bump-chain.sh <pr-number>
# Environment: GH_TOKEN, REPO, OWNER, SIGNOFF, RUN_URL; optional POLL_SECONDS (60) and
# MAX_POLLS (60, per phase); GATE_SCRIPT / WATCHDOG_SCRIPT override the scripts (tests).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
pr=${1:?usage: bump-chain.sh <pr-number>}
: "${REPO:?}" "${OWNER:?}"
RUN_URL=${RUN_URL:-}
POLL_SECONDS=${POLL_SECONDS:-60}
MAX_POLLS=${MAX_POLLS:-60}
GATE_SCRIPT=${GATE_SCRIPT:-$here/gate-run.sh}
WATCHDOG_SCRIPT=${WATCHDOG_SCRIPT:-$here/watchdog-run.sh}

say() { gh pr comment "$pr" --body "$1" </dev/null; }
pr_field() { gh pr view "$pr" --json "$1" --jq "$2" </dev/null; }

# Phase 1: PR builds
merged=false
for ((i = 0; i < MAX_POLLS; i++)); do
    head=$(pr_field headRefOid .headRefOid)
    # The gate evaluates this PR only (check_run mode), merging or reporting as it decides
    SHA=$head bash "$GATE_SCRIPT" || true
    case "$(pr_field state .state)" in
        MERGED) merged=true; break ;;
        CLOSED) echo "PR #$pr was closed without merging"; exit 1 ;;
    esac
    if pr_field comments '.comments[].body' | grep -qF "<!-- bump-gate:fail:$head -->"; then
        echo "PR #$pr: Packit builds failed; the gate commented and requested a review"
        exit 1
    fi
    echo "PR #$pr: waiting for Packit builds ($((i + 1))/$MAX_POLLS)"
    sleep "$POLL_SECONDS"
done
if [ "$merged" != true ]; then
    say "@$OWNER Gave up waiting for the Packit PR builds to finish. Workflow run: $RUN_URL"
    exit 1
fi

# Phase 2: builds of the merge commit on main
merge_sha=$(pr_field mergeCommit .mergeCommit.oid)
echo "PR #$pr merged as ${merge_sha:0:7}; waiting for the main builds"
for ((i = 0; i < MAX_POLLS; i++)); do
    git fetch -q origin main
    git switch -q --detach origin/main
    out=$(SHA=$merge_sha bash "$WATCHDOG_SCRIPT" 2>&1) || { echo "$out"; exit 1; }
    echo "$out"
    verdict=$(grep -o 'watchdog verdict [a-z]*' <<<"$out" | awk '{print $3}' | tail -n 1 || true)
    case "$verdict" in
        ok)
            say "Merged as \`${merge_sha:0:7}\` and the Packit builds on main passed. Workflow run: $RUN_URL"
            exit 0
            ;;
        revert|comment)
            echo "main builds failed; the watchdog has reported it"
            exit 1
            ;;
    esac
    sleep "$POLL_SECONDS"
done
say "@$OWNER Merged as \`${merge_sha:0:7}\` but the Packit builds on main did not finish in time, so they are unchecked. Workflow run: $RUN_URL"
exit 1
