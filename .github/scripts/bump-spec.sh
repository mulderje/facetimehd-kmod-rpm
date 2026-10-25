#!/usr/bin/env bash
# Helpers for the upstream-bump workflow.
#   bump-spec.sh latest-tag <git-url>            newest stable upstream tag, or nothing
#   bump-spec.sh needs-bump <current> <latest>   exit 0 only if latest is strictly newer
#   bump-spec.sh apply <spec> <new-tag>          update a spec to the new tag
set -euo pipefail

latest_tag() {
    git ls-remote --tags --refs "$1" \
        | sed 's#.*refs/tags/##' \
        | { grep -E '^v?[0-9]+(\.[0-9]+)*$' || true; } \
        | sort -V | tail -n 1
}

needs_bump() {
    local cur=${1#v} new=${2#v}
    [ -n "$new" ] && [ "$cur" != "$new" ] \
        && [ "$(printf '%s\n%s\n' "$cur" "$new" | sort -V | tail -n 1)" = "$new" ]
}

apply() {
    local spec=$1 tag=$2 version=${2#v} date
    date=$(LC_ALL=C date -u '+%a %b %d %Y')
    sed -i -E "s/^(%global tag[[:space:]]+).*/\1${tag}/" "$spec"
    # Only touch Version when it is a literal number; "Version: %{tag}" tracks the tag.
    sed -i -E "s/^(Version:[[:space:]]+)[0-9].*/\1${version}/" "$spec"
    sed -i -E 's/^(Release:[[:space:]]+).*/\11%{?dist}/' "$spec"
    sed -i "/^%changelog\$/a * ${date} github-actions <noreply@github.com> - ${version}-1\n- Update to ${version} release\n" "$spec"
}

case "${1:-}" in
    latest-tag) latest_tag "$2" ;;
    needs-bump) needs_bump "$2" "$3" ;;
    apply)      apply "$2" "$3" ;;
    *) echo "usage: $0 {latest-tag <url>|needs-bump <cur> <new>|apply <spec> <tag>}" >&2; exit 2 ;;
esac
