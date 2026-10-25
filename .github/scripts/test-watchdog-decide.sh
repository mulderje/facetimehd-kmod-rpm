#!/usr/bin/env bash
# Tests for watchdog-decide.sh. Run from anywhere: bash .github/scripts/test-watchdog-decide.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
decide="$here/watchdog-decide.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

# 12 successful Packit builds of a main commit: 4 Fedora targets x 3 packages
base=$(jq -n '
  ["fedora-43-x86_64","fedora-44-x86_64","fedora-45-x86_64","fedora-rawhide-x86_64"] as $c
  | ["facetimehd","facetimehd-firmware","facetimehd-kmod"] as $p
  | [ $c[] as $ch | $p[] as $pk
      | {name:"rpm-build:main:\($ch):\($pk)", status:"completed", conclusion:"success",
         html_url:"https://example.test/\($ch)/\($pk)", app:"packit-as-a-service"} ]')

driver_bump="facetimehd,facetimehd-kmod"

first_line() { bash "$decide" "$1" | head -n 1; }
check() { # check <expected> <changed> <label> <json>
    local got
    got=$(printf '%s' "$4" | first_line "$2")
    [ "$got" = "$1" ] || fail "$3: expected '$1', got '$got'"
}
with_conclusion() { # with_conclusion <check-name-suffix> <conclusion>
    jq --arg s "$1" --arg c "$2" 'map(if (.name|endswith($s)) then .conclusion=$c else . end)' <<<"$base"
}

# (a) everything green
check ok "$driver_bump" "all green" "$base"

# (b) a changed package failed: revert, and the failing check is listed
failing=$(with_conclusion ":fedora-rawhide-x86_64:facetimehd-kmod" failure)
check revert "$driver_bump" "kmod failure" "$failing"
printf '%s' "$failing" | bash "$decide" "$driver_bump" \
    | grep -qx 'FAIL rpm-build:main:fedora-rawhide-x86_64:facetimehd-kmod https://example.test/fedora-rawhide-x86_64/facetimehd-kmod' \
    || fail "failure line missing name and link"

# (c) only an unchanged package failed: comment, never revert
check comment "$driver_bump" "firmware failure after driver bump" \
    "$(with_conclusion ":fedora-44-x86_64:facetimehd-firmware" failure)"

# (d) non-failure conclusions are not a reason to revert
for c in cancelled timed_out neutral skipped; do
    check ok "$driver_bump" "kmod $c" "$(with_conclusion ":fedora-43-x86_64:facetimehd-kmod" "$c")"
done

# (e) still running
check pending "$driver_bump" "one in progress" \
    "$(jq 'map(if .name=="rpm-build:main:fedora-45-x86_64:facetimehd" then .status="in_progress" | .conclusion=null else . end)' <<<"$base")"

# (f) PR builds (no main: prefix) are ignored
check pending "$driver_bump" "PR builds only" \
    "$(jq 'map(.name |= sub("^rpm-build:main:";"rpm-build:"))' <<<"$base")"

# (g) another app's failing check is ignored
check ok "$driver_bump" "other app failure ignored" \
    "$(jq '. + [{name:"rpm-build:main:fedora-43-x86_64:facetimehd-kmod",status:"completed",conclusion:"failure",html_url:"u",app:"someone-else"}]' <<<"$base")"

# (h) firmware bump: a firmware failure now reverts
check revert "facetimehd-firmware" "firmware failure after firmware bump" \
    "$(with_conclusion ":fedora-44-x86_64:facetimehd-firmware" failure)"

echo PASS
