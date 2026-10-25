#!/usr/bin/env bash
# Tests for bump-spec.sh. Run from anywhere: bash .github/scripts/test-bump-spec.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
bump="$here/bump-spec.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# (a) kmod: tag bumped, Version stays %{tag}, Release reset, changelog added
cp "$root/facetimehd-kmod/facetimehd-kmod.spec" "$tmp/kmod.spec"
bash "$bump" apply "$tmp/kmod.spec" 0.7.2
grep -q '^%global tag 0.7.2$' "$tmp/kmod.spec" || fail "kmod tag not updated"
grep -q '^Version:[[:space:]]*%{tag}$' "$tmp/kmod.spec" || fail "kmod Version must stay %{tag}"
grep -q '^Release:[[:space:]]*1%{?dist}$' "$tmp/kmod.spec" || fail "kmod Release not reset"

# (b) firmware: v-prefixed tag, literal Version without the v
cp "$root/facetimehd-firmware/facetimehd-firmware.spec" "$tmp/fw.spec"
bash "$bump" apply "$tmp/fw.spec" v1.0.1
grep -q '^%global tag v1.0.1$' "$tmp/fw.spec" || fail "fw tag not updated"
grep -q '^Version:[[:space:]]*1.0.1$' "$tmp/fw.spec" || fail "fw Version not updated"

# (e) changelog: first entry has an RPM-style date and the new version
first=$(grep -A1 '^%changelog$' "$tmp/fw.spec" | tail -1)
echo "$first" | grep -Eq '^\* [A-Z][a-z]{2} [A-Z][a-z]{2} [0-9]{2} [0-9]{4} .* - 1\.0\.1-1$' || fail "bad changelog line: $first"

# (c) needs-bump ordering
bash "$bump" needs-bump 0.7.0.1 0.7.0.2 || fail "0.7.0.2 should be newer than 0.7.0.1"
bash "$bump" needs-bump v1.0.0 v1.0.1 || fail "v1.0.1 should be newer than v1.0.0"
! bash "$bump" needs-bump 0.7.2 0.7.2 || fail "equal tags must not bump"
! bash "$bump" needs-bump 0.7.3 0.7.2 || fail "older upstream must not downgrade"
! bash "$bump" needs-bump 0.7.0.1 "" || fail "empty latest tag must not bump"

# (d) latest-tag ignores pre-releases and sorts by version
git init -q "$tmp/up"
git -C "$tmp/up" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
for t in 0.7.0.1 0.7.0.3 0.7.2 0.7.11-rc1 0.7.10; do git -C "$tmp/up" tag "$t"; done
[ "$(bash "$bump" latest-tag "$tmp/up")" = "0.7.10" ] || fail "latest-tag wrong: $(bash "$bump" latest-tag "$tmp/up")"
git init -q "$tmp/none"
[ -z "$(bash "$bump" latest-tag "$tmp/none")" ] || fail "latest-tag on tagless repo must print nothing"

echo PASS
