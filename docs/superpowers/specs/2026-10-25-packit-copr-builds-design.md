# Packit and Copr builds for the three facetimehd packages

Date: 2026-10-25
Branch: `packit` (PR #7 into `main`)

## Goal

Make Copr builds succeed for `facetimehd`, `facetimehd-kmod` and `facetimehd-firmware`
on every active Fedora release plus rawhide (x86_64), using current Packit and RPM
practice, and track new upstream releases automatically. The Copr output is consumed
downstream (mulderje/ublue-oldair).

## Constraints

- This repo holds only specs. Upstream sources live in `patjak/facetimehd` (driver and
  metadata packages, tags like `0.7.0.1`) and `patjak/facetimehd-firmware` (tags like
  `v1.0.0`). The user does not own either, so Packit cannot be installed there.
- x86_64 only. The camera (Broadcom 1570) is in 2013+ MacBooks, all 64-bit, and the
  firmware extractor only supports x86.
- PR #5 (kmodtool scratch test) is out of scope and must not be touched.
- Commits go to the `packit` branch, which updates PR #7 and triggers the Copr PR builds.

## Findings (PR #7, head 46880a0)

- `facetimehd`: builds pass on 43, 44, 45, rawhide, but only by accident (see below).
- `facetimehd-kmod`: `%prep` fails, `cd: facetimehd-0.7.0.1: No such file or directory`.
- `facetimehd-firmware`: `%build` fails, `make: *** No targets specified and no makefile found`.
- Root cause: PR #7 removed the per-package `create-archive` actions. Packit then
  archives this spec-only repo and uses it as `Source`, so no upstream code is present.
  `facetimehd` passes only because it needs no source files, and it ships this repo's
  `LICENSE` rather than upstream's.
- Other config defects: `propose_downstream` and `files_to_sync` target Fedora dist-git
  (Packit docs: release jobs create dist-git pull requests; the Packit app must be on the
  upstream repo), which does not apply here. `owner`/`project` for the Copr targets were
  dropped or merged into one field.

## Design

### 1. `.packit.yaml`

- Per-package `actions` (`create-archive`, `get-current-version`) fetch the real upstream
  tarball with `spectool -g` from the spec's `Source`, and read the version with
  `rpmspec`. Each action prints the archive name as Packit requires.
- Remove `upstream_package_name`, `files_to_sync` and the `propose_downstream` job.
- Jobs:
  - `copr_build`, trigger `pull_request`, owner `mulderje`, project
    `facetimehd-kmod-pr`.
  - `copr_build`, trigger `commit`, branch `main`, owner `mulderje`, project
    `facetimehd-kmod`.
  - Targets `fedora-all-x86_64` for all three packages.
  - `enable_net: true` only on the firmware jobs (its Makefile downloads Apple's
    installer at `%build`). Separate job entries for firmware, so the other packages
    build without network.

### 2. Spec changes (minimal, build-driven)

- `facetimehd-kmod`: `ExclusiveArch: x86_64` (drop `i686` and its stale comment), drop the
  unneeded `rpmdevtools` BuildRequires if the build does not need it.
- `facetimehd`: ships upstream `LICENSE` once the real tarball is used (no edit expected).
- `facetimehd-firmware`: already `BuildArch: noarch`; no change expected.
- Anything else only if a Copr build fails on it. No speculative refactors.

### 3. Upstream release tracking: `.github/workflows/upstream-bump.yml`

- Triggers: daily schedule and `workflow_dispatch`.
- For each upstream, find the newest tag and compare with the spec's `%global tag`.
- If newer, edit the affected specs, reset `Release` to 1, add a `%changelog` entry, and
  open one PR per upstream (`facetimehd` and `facetimehd-kmod` share one) with a pinned
  `peter-evans/create-pull-request`. The PR then triggers the Packit Copr PR builds.
- Known risk: PRs opened with the default `GITHUB_TOKEN` do not start other GitHub
  Actions workflows. Packit is a GitHub App listening for PR webhooks and should still
  fire; this is verified after the first bump PR. Fallback: a fine-grained PAT stored as
  a repo secret (to be created by the user).
- All third-party actions pinned by commit SHA. Workflow permissions limited to
  `contents: write` and `pull-requests: write`.
- Note: upstream already has tags newer than the specs (`0.7.0.2`, `0.7.0.3`, `0.7.2`).
  The first workflow run will propose that bump. Bumping versions is not part of this
  change.

### 4. Docs

- README: replace the unchecked `pull_from_upstream` TODO with a note on the Action-based
  bumps, and describe the Packit/Copr flow.

## Verification

- Push to `packit`; PR #7 builds run on Copr. Read build logs through the Packit API
  (`prod.packit.dev/api/copr-builds/<id>`) and Copr results.
- Success: all 12 Copr checks (3 packages x fedora 43, 44, 45, rawhide) green, and
  `rpm -qp --scripts`/file lists show `facetimehd` shipping upstream `LICENSE`.
- Local checks where tools exist (`rpmspec -P`, `rpmlint`, `actionlint` or YAML parse for
  the workflow). The sandbox has no rpm tooling, so Copr is the authoritative test.
- Workflow verified with `workflow_dispatch` on the branch before relying on the schedule.

## Out of scope

- PR #5 and kmodtool patch testing.
- Fedora dist-git submission and `pull_from_upstream`.
- Bumping package versions to the newer upstream tags.
