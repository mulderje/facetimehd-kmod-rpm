#!/usr/bin/env bash
# Stand-in for the gh CLI, used by test-gate-run.sh and test-watchdog-run.sh (copied to a
# directory on PATH as "gh"). It serves canned JSON, applies --jq with the real jq, and
# logs every call to $GH_CALLS (including comment bodies).
#
#   GH_PULLS         JSON array served for repos/*/pulls?... and repos/*/commits/*/pulls
#   GH_CHECKS        JSON object {check_runs: [...]} served for .../check-runs
#   GH_COMMENTS      JSON object {comments: [...]} for "gh pr view --json comments"
#   GH_MERGE_RC      exit status of "gh pr merge" (default 0)
set -uo pipefail
{
    echo "gh $*"
    prev=
    for a in "$@"; do
        if [ "$prev" = "--body-file" ] && [ -f "$a" ]; then sed 's/^/    | /' "$a"; fi
        prev=$a
    done
} >> "$GH_CALLS"

jq_expr=
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    [ "${args[$i]}" = "--jq" ] && jq_expr=${args[$((i + 1))]}
done

case "${1:-} ${2:-}" in
    "api "*)
        url=$2; [ "$2" = "--paginate" ] && url=$3
        case "$url" in
            *check-runs*)            file=$GH_CHECKS ;;
            */commits/*/pulls*|*/pulls\?*) file=$GH_PULLS ;;
            *) echo "fake-gh: unexpected api url $url" >&2; exit 1 ;;
        esac
        jq -r "$jq_expr" "$file"
        ;;
    "pr view")
        case "$*" in
            *"--json comments"*) jq -r "$jq_expr" "$GH_COMMENTS" ;;
            *"--json title"*)    echo "Update facetimehd to 0.7.3" ;;
            *"--json state"*)    echo "${GH_PR_STATE:-OPEN}" ;;
        esac
        ;;
    "pr merge")  exit "${GH_MERGE_RC:-0}" ;;
    "pr create") echo "https://example.test/pull/99" ;;
esac
exit 0
