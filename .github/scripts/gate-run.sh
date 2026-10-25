#!/usr/bin/env bash
# Gate the bot's bump/revert PRs: squash-merge when every Packit PR build passed,
# otherwise explain why and ask the owner to review.
#
# With SHA set (a check_run event) only the PR whose head is that commit is considered.
# Without it (scheduled sweep or manual dispatch) every open bot PR is. The sweep exists
# because check_run events are not delivered for PRs opened with the workflow token.
#
# A green PR labelled ci-test (a forced pipeline test), or any PR when SMOKE=true, is closed and its branch deleted
# instead of merged, so tests leave nothing on main.
#
# Environment: GH_TOKEN, REPO, OWNER, SIGNOFF, optional SHA, SMOKE and RUN_URL. Needs gh and jq.
# Decision logic: pr-gate.sh (tested by test-pr-gate.sh).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${REPO:?}" "${OWNER:?}" "${SIGNOFF:?}"
RUN_URL=${RUN_URL:-}
export SHA=${SHA:-}

bot_prs='.[] | select(.state == "open")
             | select(.user.login | endswith("[bot]"))
             | select(.head.ref | test("^(bump|revert)/"))'
if [ -n "$SHA" ]; then
    candidates=$(gh api "repos/$REPO/commits/$SHA/pulls" \
        --jq "$bot_prs | select(.head.sha == env.SHA) | \"\(.number) \(.head.sha)\"")
else
    candidates=$(gh api "repos/$REPO/pulls?state=open&per_page=100" \
        --jq "$bot_prs | \"\(.number) \(.head.sha)\"")
fi
if [ -z "$candidates" ]; then
    echo "No bot bump/revert PRs to gate"
    exit 0
fi

checks=$(mktemp)
while read -r n sha <&3; do
    gh api --paginate "repos/$REPO/commits/$sha/check-runs?per_page=100" \
        --jq '.check_runs[] | {name, status, conclusion, html_url, app: .app.slug}' \
        | jq -s . > "$checks"
    result=$(bash "$here/pr-gate.sh" < "$checks")
    verdict=$(head -n 1 <<<"$result")
    echo "PR #$n (${sha:0:7}): $verdict"

    case "$verdict" in
        pending)
            ;;
        fail)
            marker="<!-- bump-gate:fail:$sha -->"
            if gh pr view "$n" --json comments --jq '.comments[].body' </dev/null | grep -qF "$marker"; then
                echo "PR #$n: failure already reported"
                continue
            fi
            {
                echo "@$OWNER needs your review. Not merging: Packit builds failed for \`${sha:0:7}\`."
                echo
                tail -n +2 <<<"$result" | sed -E 's/^FAIL ([^ ]+) (.*)$/- `\1`: \2/'
                echo
                echo "Workflow run: $RUN_URL"
                echo "$marker"
            } > comment.md
            gh pr comment "$n" --body-file comment.md </dev/null
            # Ask the owner for a review so it shows up in their notifications
            gh pr edit "$n" --add-reviewer "$OWNER" --add-label needs-review </dev/null \
                || gh pr edit "$n" --add-reviewer "$OWNER" </dev/null || true
            ;;
        pass)
            state=$(gh pr view "$n" --json state --jq .state </dev/null || true)
            if [ "$state" = "MERGED" ]; then
                echo "PR #$n: already merged"
                continue
            fi
            # The label travels with the PR, so every gate run (event, sweep, bump run) agrees
            smoke=${SMOKE:-}
            if gh pr view "$n" --json labels --jq '.labels[].name' </dev/null | grep -qx ci-test; then
                smoke=true
            fi
            if [ "$smoke" = "true" ]; then
                gh pr close "$n" --delete-branch --comment "Pipeline test passed: all Packit builds are green. Closed without merging. Workflow run: $RUN_URL
<!-- bump-gate:smoke-passed:$sha -->" </dev/null
                continue
            fi
            title=$(gh pr view "$n" --json title --jq .title </dev/null)
            body=$(printf 'Merged automatically after all Packit builds passed.\n\n%s' "$SIGNOFF")
            if gh pr merge "$n" --squash --delete-branch --subject "$title (#$n)" --body "$body" </dev/null; then
                gh pr comment "$n" --body "Merged after all Packit builds passed. Workflow run: $RUN_URL" </dev/null
            else
                # Another run (a sweep, the bump workflow) may have merged it in the meantime
                state=$(gh pr view "$n" --json state --jq .state </dev/null || true)
                if [ "$state" = "MERGED" ]; then
                    echo "PR #$n: merged by another run"
                    continue
                fi
                marker="<!-- bump-gate:merge-failed:$sha -->"
                if ! gh pr view "$n" --json comments --jq '.comments[].body' </dev/null | grep -qF "$marker"; then
                    gh pr comment "$n" --body "@$OWNER All Packit builds passed but the merge failed (conflict or branch rules), so it needs a manual merge. Workflow run: $RUN_URL
$marker" </dev/null
                    gh pr edit "$n" --add-reviewer "$OWNER" </dev/null || true
                fi
            fi
            ;;
    esac
done 3<<<"$candidates"
