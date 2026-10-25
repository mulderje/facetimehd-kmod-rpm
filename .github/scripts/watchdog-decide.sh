#!/usr/bin/env bash
# Decide what to do about the Packit builds of a main commit that came from a bump PR.
#
# Usage: watchdog-decide.sh <changed-packages-csv>   (check runs as JSON on stdin)
# Input: JSON array of {name, status, conclusion, html_url, app}.
# Output: first line "pending", "ok", "revert" or "comment"; then one
# "FAIL <name> <html_url>" line per failed build. Always exits 0.
#
# Only Packit main builds count (rpm-build:main:<chroot>:<package>). Only a "failure"
# conclusion matters; cancelled, timed_out and the like are ignored so infrastructure
# trouble does not cause reverts. A revert needs a failing package that the bump
# changed; failures in other packages only get a comment.
set -euo pipefail

changed=${1:?usage: watchdog-decide.sh <changed-packages-csv>}

jq -r --arg changed "$changed" '
  ($changed | split(",")) as $changed_pkgs
  | [ .[]
      | select(.app == "packit-as-a-service")
      | select(.name | startswith("rpm-build:main:")) ] as $c
  | [ $c[] | select(.conclusion == "failure") ] as $failed
  | if ($c | length) == 0 or ($c | any(.status != "completed")) then
      "pending"
    elif ($failed | length) == 0 then
      "ok"
    else
      (if ($failed | any(.name | split(":") | last | IN($changed_pkgs[]))) then "revert" else "comment" end),
      ($failed[] | "FAIL \(.name) \(.html_url)")
    end
'
