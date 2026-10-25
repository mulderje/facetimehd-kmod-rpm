#!/usr/bin/env bash
# Tests for pr-gate.sh. Run from anywhere: bash .github/scripts/test-pr-gate.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
gate="$here/pr-gate.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

# 12 successful Packit PR builds: 4 Fedora targets x 3 packages
base=$(jq -n '
  ["fedora-43-x86_64","fedora-44-x86_64","fedora-45-x86_64","fedora-rawhide-x86_64"] as $c
  | ["facetimehd","facetimehd-firmware","facetimehd-kmod"] as $p
  | [ $c[] as $ch | $p[] as $pk
      | {name:"rpm-build:\($ch):\($pk)", status:"completed", conclusion:"success",
         html_url:"https://example.test/\($ch)/\($pk)", app:"packit-as-a-service"} ]')

first_line() { bash "$gate" | head -n 1; }
check() { # check <expected> <label> <json>
    local got
    got=$(printf '%s' "$3" | first_line)
    [ "$got" = "$1" ] || fail "$2: expected '$1', got '$got'"
}

# (a) all green, plus a neutral osh scan that must be ignored
check pass "all green with osh neutral" \
    "$(jq '. + [{name:"osh-diff-scan:fedora-rawhide-x86_64:facetimehd-kmod",status:"completed",conclusion:"neutral",html_url:"u",app:"packit-as-a-service"}]' <<<"$base")"

# (b) one build still running
check pending "one in progress" \
    "$(jq 'map(if .name=="rpm-build:fedora-45-x86_64:facetimehd" then .status="in_progress" | .conclusion=null else . end)' <<<"$base")"

# (c) only two packages have reported
check pending "two packages only" \
    "$(jq 'map(select(.name|endswith(":facetimehd-kmod")|not))' <<<"$base")"

# (d) a failure is reported with its name and link
failing=$(jq 'map(if .name=="rpm-build:fedora-44-x86_64:facetimehd-kmod" then .conclusion="failure" else . end)' <<<"$base")
check fail "one failure" "$failing"
printf '%s' "$failing" | bash "$gate" | grep -qx 'FAIL rpm-build:fedora-44-x86_64:facetimehd-kmod https://example.test/fedora-44-x86_64/facetimehd-kmod' \
    || fail "failure line missing name and link"

# (e) a cancelled build blocks the merge
check fail "cancelled" \
    "$(jq 'map(if .name=="rpm-build:fedora-43-x86_64:facetimehd" then .conclusion="cancelled" else . end)' <<<"$base")"

# (f) main-branch builds alone are not PR builds
check pending "main builds only" \
    "$(jq 'map(.name |= sub("^rpm-build:";"rpm-build:main:"))' <<<"$base")"

# (g) failures from other apps are ignored
check pass "other app failure ignored" \
    "$(jq '. + [{name:"rpm-build:fedora-43-x86_64:facetimehd",status:"completed",conclusion:"failure",html_url:"u",app:"someone-else"}]' <<<"$base")"

# (h) no checks at all
check pending "empty" "[]"

echo PASS
