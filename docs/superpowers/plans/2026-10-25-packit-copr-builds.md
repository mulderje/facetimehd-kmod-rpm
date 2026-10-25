# Packit and Copr builds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get Copr builds green for `facetimehd`, `facetimehd-kmod` and `facetimehd-firmware` on PR #7, and add automatic upstream version-bump PRs.

**Architecture:** `main`'s `.packit.yaml` already built all three packages on Copr (builds 10348776 to 10348778, five chroots, all succeeded). PR #7 broke it by dropping the per-package `create-archive` actions. Task 1 restores that known-good baseline, later tasks modernize on top of a green PR. Release tracking is a scheduled GitHub Action plus a small tested shell script, since Packit release jobs only target Fedora dist-git.

**Tech Stack:** Packit (`.packit.yaml`), Copr, RPM specs (forge macros, kmodtool), GitHub Actions, bash.

**Spec:** `docs/superpowers/specs/2026-10-25-packit-copr-builds-design.md`

## Global Constraints

- Work on branch `packit` only (PR #7 into `main`). Never push to `main`. Leave PR #5 alone.
- x86_64 only: Packit targets `fedora-all-x86_64`; `facetimehd-kmod` gets `ExclusiveArch: x86_64`.
- Copr PR project `mulderje/facetimehd-kmod-pr`; Copr `main` project `mulderje/facetimehd-kmod`; `owner` and `project` are separate keys.
- `enable_net: true` on the firmware jobs only (its Makefile downloads Apple's installer at `%build`).
- Upstream tags: `patjak/facetimehd` uses `0.7.0.1` style (no prefix); `patjak/facetimehd-firmware` uses `v1.0.0` style.
- No `propose_downstream`, `pull_from_upstream` or `files_to_sync` (Fedora dist-git only).
- Third-party GitHub Actions pinned by commit SHA; workflow permissions limited to `contents: write` and `pull-requests: write`.
- Do not bump package versions to newer upstream tags as part of this work.
- Every commit ends with the attribution trailers from the session reminder.
- Authoritative test is the 12 PR checks on Copr (3 packages x fedora 43, 44, 45, rawhide). Read logs via `https://prod.packit.dev/api/copr-builds/<packit job id>` then the `build_logs_url` (`.log.gz`).

## Review Focus

- Upstream pre-release tags (for example `0.7.2-rc1`) must be ignored by the bump script, not proposed.
- If the spec's tag is newer than or equal to upstream's latest, the script must make no change (no downgrade, no empty PR).
- Both tag styles (`0.7.2` and `v1.0.1`) must round-trip into the spec's `%global tag` and literal `Version:` correctly.
- Firmware build depends on Apple's download at build time; a network failure there is an upstream/outage failure, not a packaging bug, and must be reported as such.
- A bump PR opened with `GITHUB_TOKEN` might not trigger Packit; check it fires, otherwise a PAT is needed.

---

### Task 1: Restore the known-good Packit config

**Files:**
- Modify: `.packit.yaml` (replace with the version on `main`, then adjust)

**Interfaces:**
- Produces: a `.packit.yaml` whose `packages:` keys are `facetimehd`, `facetimehd-kmod`, `facetimehd-firmware`, each with `paths`, `specfile_path` and a `create-archive` action. Later tasks edit those actions.

- [ ] **Step 1: Restore from `main`.** Run `git checkout origin/main -- .packit.yaml` (fetch first). Confirm `git diff origin/main -- .packit.yaml` is empty.
- [ ] **Step 2: Split firmware into its own job pair.** In both `copr_build` jobs keep `enable_net: true` only for `packages: [facetimehd-firmware]`; add a second job per trigger for `[facetimehd, facetimehd-kmod]` without `enable_net`. Keep `owner`/`project` and `targets: [fedora-all-x86_64]` on every job.
- [ ] **Step 3: Validate YAML.** Run `python3 -c "import yaml;yaml.safe_load(open('.packit.yaml'))"`; expected: no output, exit 0.
- [ ] **Step 4: Commit and push to `packit`.** Message: `Restore working Packit config and scope enable_net to firmware`.
- [ ] **Step 5: Verify on Copr.** Wait for the PR checks; read them with the `get_check_runs` of PR #7. Expected: all 12 `rpm-build:*` checks `success`. If a firmware build fails, read its log: a network error fetching Apple's installer means `enable_net` did not apply, so check the job is the one with `enable_net: true`; any other error is a real build failure to fix before continuing.

### Task 2: x86_64 only for the kmod

**Files:**
- Modify: `facetimehd-kmod/facetimehd-kmod.spec` (the `ExclusiveArch` line and the comment above it)

**Interfaces:**
- Consumes: green baseline from Task 1.

- [ ] **Step 1: Edit.** Change `ExclusiveArch:  i686 x86_64` to `ExclusiveArch:  x86_64` and delete the two comment lines referring to plague and ppc. Add a `%changelog` entry at the top: author `Jon Mulder <jon.e.mulder@gmail.com>`, text `Restrict to x86_64 (no i686 kernels in Fedora)`.
- [ ] **Step 2: Commit and push.**
- [ ] **Step 3: Verify.** All 12 PR checks still `success`; the kmod `Provides`/`akmod-facetimehd` still appear in the build log's `Wrote:` lines.

### Task 3: Derive source download from the spec

**Files:**
- Modify: `.packit.yaml` (the `create-archive` and added `get-current-version` actions for all three packages)

**Interfaces:**
- Consumes: Task 1 config. Each package's `create-archive` must print the archive file name as its last stdout line (Packit contract).

- [ ] **Step 1: Replace hardcoded curl URLs.** For each package, `create-archive` runs `spectool -g <spec>` in the package directory (the spec's `Source:` already resolves through `%forgesource`) and then prints the downloaded tarball name found via `spectool -l <spec>`. Add `get-current-version` that prints `rpmspec -q --qf '%{version}\n' --srpm <spec> | head -1`.
- [ ] **Step 2: Validate YAML** as in Task 1 Step 3.
- [ ] **Step 3: Commit and push.**
- [ ] **Step 4: Verify.** All 12 checks `success`. If `spectool` is missing in Packit's SRPM environment or the tarball name does not match what the spec's `Source0` expects, revert this single commit (`git revert`), keep Task 1's curl actions, and note in the spec doc that Packit's environment lacked the tool. Do not hand-patch around it.

### Task 4: Tested spec bump script

**Files:**
- Create: `.github/scripts/bump-spec.sh`
- Create: `.github/scripts/test-bump-spec.sh`

**Interfaces:**
- Produces: `bump-spec.sh latest-tag <git-url>` prints the newest stable tag (matching `^v?[0-9]+(\.[0-9]+)*$`, sorted by version) or nothing; `bump-spec.sh needs-bump <current-tag> <latest-tag>` exits 0 only if latest is strictly newer by `sort -V`; `bump-spec.sh apply <spec-path> <new-tag>` rewrites `%global tag`, a literal `Version:` (strip leading `v`; leave `Version: %{tag}` alone), sets `Release:` to `1%{?dist}`, and inserts a `%changelog` entry `* <date, LC_ALL=C %a %b %d %Y> github-actions <noreply@github.com> - <version>-1` / `- Update to <version> release`.

- [ ] **Step 1: Write the failing test** `test-bump-spec.sh`: copies each of the three specs to a temp dir, then asserts with `grep`: (a) `apply` on kmod with `0.7.2` gives `%global tag 0.7.2` and keeps `Version:       %{tag}`; (b) `apply` on firmware with `v1.0.1` gives `%global tag v1.0.1` and `Version:        1.0.1`; (c) `needs-bump 0.7.2 0.7.2` and `needs-bump 0.7.3 0.7.2` exit non-zero, `needs-bump 0.7.0.1 0.7.0.2` exits 0; (d) `latest-tag` on a local bare repo with tags `0.7.0.1 0.7.0.3 0.7.2 0.7.3-rc1` prints `0.7.2`; (e) the changelog's first entry date line matches `^\* [A-Z][a-z]{2} [A-Z][a-z]{2} [0-9]{2} [0-9]{4} `.
- [ ] **Step 2: Run and see it fail.** `bash .github/scripts/test-bump-spec.sh`; expected: fails with "bump-spec.sh: No such file".
- [ ] **Step 3: Implement** `bump-spec.sh` with the three subcommands above (plain bash, `set -euo pipefail`, uses `git ls-remote --tags --refs`, `sort -V`, `sed`).
- [ ] **Step 4: Run the test.** Expected: prints `PASS` and exits 0.
- [ ] **Step 5: Commit and push.**

### Task 5: Upstream bump workflow

**Files:**
- Create: `.github/workflows/upstream-bump.yml`

**Interfaces:**
- Consumes: `bump-spec.sh` subcommands from Task 4.

- [ ] **Step 1: Write the workflow.** Triggers `schedule` (daily) and `workflow_dispatch`. Job `test` runs `test-bump-spec.sh`. Job `bump` (needs `test`) has a matrix of two entries: `{upstream: https://github.com/patjak/facetimehd, specs: facetimehd/facetimehd.spec facetimehd-kmod/facetimehd-kmod.spec, branch: bump/facetimehd}` and `{upstream: https://github.com/patjak/facetimehd-firmware, specs: facetimehd-firmware/facetimehd-firmware.spec, branch: bump/facetimehd-firmware}`. Steps: checkout (pinned SHA), read current tag from the first spec's `%global tag`, `latest-tag`, `needs-bump`, `apply` to each spec, then `peter-evans/create-pull-request` (pinned SHA) with base `main`, the matrix branch, title `Update <name> to <version>`. Skip cleanly if no bump is needed.
- [ ] **Step 2: Validate.** Run `python3 -c "import yaml;yaml.safe_load(open('.github/workflows/upstream-bump.yml'))"`; if `actionlint` is installable (`pip download` unavailable offline is fine), run it too. Expected: no errors.
- [ ] **Step 3: Commit and push.**
- [ ] **Step 4: Dry check.** `workflow_dispatch` only runs once the workflow exists on the default branch, so on `packit` verify by running `bump-spec.sh latest-tag` against both real upstream URLs locally (expected: `0.7.2` and `v1.0.0`) and by reading the workflow once more against Task 4's interfaces. Record in the PR that the first live run happens after merge, and that the first bump PR must be checked for Packit builds starting (Review Focus item 5).

### Task 6: README

**Files:**
- Modify: `README.md` (the Best practices checklist near the top)

- [ ] **Step 1: Edit.** Replace the unchecked `pull_from_upstream` item with `- [x] New upstream tags open bump PRs via .github/workflows/upstream-bump.yml` and add one line noting Packit builds each PR in `mulderje/facetimehd-kmod-pr` and each `main` push in `mulderje/facetimehd-kmod`.
- [ ] **Step 2: Commit and push.**
- [ ] **Step 3: Final verification.** All 12 PR checks `success` on the head commit; `git status` clean; report the PR #7 head SHA and check results to the user.
