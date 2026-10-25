#!/usr/bin/env bash
# Watch the Packit builds of main commits that came from a merged bot bump PR. If a
# package the bump changed failed to build, open a revert PR (merged by gate-run.sh once
# its own builds pass) and say why; if only other packages failed, just comment.
#
# With SHA set (a check_run event) only that commit is examined. Without it (scheduled
# sweep or manual dispatch) the latest commits on main are, because check_run events are
# not reliably delivered for commits merged with the workflow token. Everything is
# idempotent: a hidden marker comment and the revert branch name stop repeats.
#
# Environment: GH_TOKEN, REPO, OWNER, optional SHA and RUN_URL. Run from a full clone.
# Decision logic: watchdog-decide.sh (tested by test-watchdog-decide.sh).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${REPO:?}" "${OWNER:?}"
RUN_URL=${RUN_URL:-}
SHA=${SHA:-}
SWEEP_COMMITS=${SWEEP_COMMITS:-20}

check_commit() {
    local sha=$1 pr changed result verdict marker failures branch title revert_pr checks

    # Only commits on main from a merged bot bump PR are watched. Revert merges and manual
    # commits are ignored, so a failing revert cannot loop.
    git merge-base --is-ancestor "$sha" origin/main || { echo "${sha:0:7}: not on main"; return 0; }
    pr=$(gh api "repos/$REPO/commits/$sha/pulls" --jq '
        [ .[] | select(.merged_at != null)
              | select(.user.login | endswith("[bot]"))
              | select(.head.ref | test("^bump/")) | .number ] | first // empty' </dev/null)
    if [ -z "$pr" ]; then
        echo "${sha:0:7}: not from a bump PR"
        return 0
    fi

    changed=$(git show --name-only --format= "$sha" | cut -d/ -f1 | sort -u \
        | grep -xE 'facetimehd|facetimehd-kmod|facetimehd-firmware' | paste -sd, - || true)
    if [ -z "$changed" ]; then
        echo "${sha:0:7}: no package directory changed"
        return 0
    fi

    checks=$(mktemp)
    gh api --paginate "repos/$REPO/commits/$sha/check-runs?per_page=100" \
        --jq '.check_runs[] | {name, status, conclusion, html_url, app: .app.slug}' </dev/null \
        | jq -s . > "$checks"
    result=$(bash "$here/watchdog-decide.sh" "$changed" < "$checks")
    verdict=$(head -n 1 <<<"$result")
    echo "${sha:0:7}: watchdog verdict $verdict (changed: $changed)"
    case "$verdict" in pending|ok) return 0 ;; esac

    marker="<!-- watchdog:$sha -->"
    if gh pr view "$pr" --json comments --jq '.comments[].body' </dev/null | grep -qF "$marker"; then
        echo "${sha:0:7}: already reported"
        return 0
    fi
    failures=$(tail -n +2 <<<"$result" | sed -E 's/^FAIL ([^ ]+) (.*)$/- `\1`: \2/')

    if [ "$verdict" = "comment" ]; then
        gh pr comment "$pr" --body "@$OWNER Packit builds of \`${sha:0:7}\` on main failed, but only in packages this bump did not change (changed: \`$changed\`), so nothing was reverted.

$failures

Workflow run: $RUN_URL
$marker" </dev/null
        return 0
    fi

    # verdict = revert
    branch="revert/${sha:0:7}"
    if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
        echo "$branch already exists"
        return 0
    fi
    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    git switch -q -C "$branch" origin/main
    if ! git revert --no-edit "$sha"; then
        git revert --abort || true
        git switch -q --detach origin/main
        git branch -q -D "$branch" || true
        gh pr comment "$pr" --body "@$OWNER Packit builds of \`${sha:0:7}\` on main failed, but the automatic revert hit conflicts, so please revert it manually.

$failures

Workflow run: $RUN_URL
$marker" </dev/null
        return 0
    fi
    git push -q origin "$branch"
    git switch -q --detach origin/main
    git branch -q -D "$branch" || true
    title="Revert \"$(git log -1 --format=%s "$sha")\""
    revert_pr=$(gh pr create --base main --head "$branch" --title "$title" --body "@$OWNER Automatic revert of \`${sha:0:7}\` (#$pr): Packit builds of main failed for a package this bump changed (\`$changed\`).

$failures

This PR merges itself once its own Packit builds pass. The next daily upstream-bump run opens a new bump PR, which must pass its builds again before it merges.

Workflow run: $RUN_URL

Signed-off-by: Jon Mulder <jon.e.mulder@gmail.com>" </dev/null)
    gh pr edit "$revert_pr" --add-reviewer "$OWNER" </dev/null || true
    gh pr comment "$pr" --body "@$OWNER Packit builds of \`${sha:0:7}\` on main failed, so it is being reverted in $revert_pr.

$failures

Workflow run: $RUN_URL
$marker" </dev/null
}

if [ -n "$SHA" ]; then
    check_commit "$SHA"
else
    for sha in $(git log origin/main -n "$SWEEP_COMMITS" --format=%H); do
        check_commit "$sha"
    done
fi
