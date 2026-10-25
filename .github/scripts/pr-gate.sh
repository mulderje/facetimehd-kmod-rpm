#!/usr/bin/env bash
# Decide whether a bump PR may merge, from its check runs.
#
# Input (stdin): JSON array of {name, status, conclusion, html_url, app}.
# Output: first line "pass", "pending" or "fail"; for "fail", one
# "FAIL <name> <html_url>" line per failing check. Always exits 0.
#
# Only Packit PR builds count (rpm-build:<chroot>:<package>, not rpm-build:main:*).
# Anything else, such as osh-diff-scan, is ignored. Results are pending until every
# build has completed and all three packages have reported.
set -euo pipefail

MIN_PACKAGES=3

jq -r --argjson min "$MIN_PACKAGES" '
  [ .[]
    | select(.app == "packit-as-a-service")
    | select(.name | startswith("rpm-build:"))
    | select(.name | startswith("rpm-build:main:") | not) ] as $c
  | ($c | map(.name | split(":") | last) | unique | length) as $packages
  | if ($c | length) == 0 or ($c | any(.status != "completed")) or $packages < $min then
      "pending"
    elif ($c | any(.conclusion != "success")) then
      "fail",
      ($c[] | select(.conclusion != "success") | "FAIL \(.name) \(.html_url)")
    else
      "pass"
    end
'
