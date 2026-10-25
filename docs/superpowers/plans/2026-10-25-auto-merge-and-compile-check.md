# Auto-merge, main watchdog and compile check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let upstream version bumps merge automatically when Packit builds (now including a real module compile) pass, and revert them with a clear message when the `main` builds fail.

**Architecture:** Packaging changes make Packit's results meaningful (`%check` compile in the kmod spec, retry in firmware, blacklist file). Two decision scripts (`pr-gate.sh`, `watchdog-decide.sh`) are pure functions over check-run JSON and are unit-tested; two thin workflows call them and act through `gh`.

**Tech Stack:** RPM specs, Packit, GitHub Actions, bash, `jq`, `gh`.

**Spec:** `docs/superpowers/specs/2026-10-25-auto-merge-and-compile-check-design.md`

## Global Constraints

- Work on branch `auto-merge-design`. Never push to `main`. Leave PR #5 and PR #8 alone (PR #8 is the bump bot's).
- Everything that can runs in native GitHub CI (`ci.yml`) and on Packit/Copr (test builds and package distribution). The user approved opening the PR for this branch.
- Package directories: `facetimehd/`, `facetimehd-kmod/`, `facetimehd-firmware/`. Check names: PR builds `rpm-build:<chroot>:<package>`, `main` builds `rpm-build:main:<chroot>:<package>`, from app slug `packit-as-a-service`. `osh-diff-scan:*` checks are always ignored.
- Branch prefixes the automation acts on: `bump/*` (from `upstream-bump.yml`) and `revert/*` (from the watchdog).
- Workflow permissions: `contents: write`, `pull-requests: write`, `checks: read`. Third-party actions pinned by SHA (reuse `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1`). Prefer plain `gh` and bash over new actions.
- x86_64 only; the 12-check Packit matrix (3 packages x Fedora 43, 44, 45, rawhide) is unchanged.
- Every commit ends with the attribution trailers from the session reminder. Do not use force pushes.
- No em dashes in docs, comments or messages.

## Review Focus

- Packit creates all check runs up front: the gate must not merge when only some have finished (pending when any is incomplete or fewer than 3 packages have reported).
- `cancelled` or `timed_out` PR builds must block a merge (gate: fail) but must never trigger a `main` revert (watchdog: only `failure` counts).
- A firmware-only failure after a driver bump (changed packages: `facetimehd`, `facetimehd-kmod`) must produce a comment, not a revert.
- A failing `main` build for a `revert/*` merge or a manual commit must not trigger another revert (no loops).
- Twelve check-run events arrive per commit: repeated runs must not duplicate comments, merges or revert PRs (markers and existing-branch checks).

---

### Task 1: Packaging changes and the compile check

**Files:**
- Modify: `facetimehd-kmod/facetimehd-kmod.spec` (BuildRequires line; new `%check` section before `%changelog`; changelog)
- Modify: `facetimehd/facetimehd.spec` (`%install`, `%files`, changelog)
- Modify: `facetimehd-firmware/facetimehd-firmware.spec` (`%build`, changelog)
- Modify: `.packit.yaml` (firmware `pull_request` job)

**Interfaces:**
- Produces: a Packit PR whose 12 `rpm-build` checks include a real compile of the driver on every target.

- [ ] **Step 1: Kmod spec.** Replace `BuildRequires:  kernel-devel` with `%{!?kernels:BuildRequires: kernel-devel}`. Add a `%check` section that, only when `%{?kernels}` is empty, sets `kdir` to the newest directory under `%{_usrsrc}/kernels` (`sort -V`), copies `%{srcname}-%{version}` to `_kmod_check`, and runs `make -C "$kdir" M="$PWD/_kmod_check" modules`. Comment why (akmod builds compile nothing otherwise) and that akmods' rebuild defines `kernels`, so it skips. Add a changelog bullet.
- [ ] **Step 2: facetimehd spec.** In `%install` create `%{buildroot}%{_sysconfdir}/modprobe.d/facetimehd.conf` (mode 0644, via the same `install -d` / `install -p -m 0644 /dev/stdin ... <<'EOF'` style as the modules-load file) containing a one-line comment and `blacklist bdc_pci`. List it in `%files` as `%config(noreplace) %{_sysconfdir}/modprobe.d/facetimehd.conf`. Changelog bullet.
- [ ] **Step 3: firmware spec.** Wrap the existing `%make_build ...` line in `%build` in `for i in 1 2 3; do ... && break; [ "$i" -eq 3 ] && exit 1; sleep 15; done`. Changelog bullet.
- [ ] **Step 4: `.packit.yaml`.** Add `osh_diff_scan_after_copr_build: false` to the firmware `copr_build` job with `trigger: pull_request` only. Validate: `python3 -c "import yaml;d=yaml.safe_load(open('.packit.yaml'));print([j.get('osh_diff_scan_after_copr_build') for j in d['jobs']])"`. Expected: `[None, False, None, None]`.
- [ ] **Step 5: Commit, push, wait for Packit on the existing PR.** Expected: all 12 `rpm-build` checks `success`; the kmod build log's `Executing(%check)` section shows a `make -C /usr/src/kernels/... modules` run and `Wrote:` lines still list `akmod-facetimehd` and `kmod-facetimehd`; the firmware PR job no longer reports an `osh-diff-scan` check.
- [ ] **Step 6: Negative test.** Push a temporary commit that adds `false` as the first line of the `%check` body. Expected: the four `facetimehd-kmod` checks go `failure` with `Bad exit status ... (%check)` in the log, the other eight stay green. Then `git revert` that commit and push. Expected: 12 green again.

### Task 1b: CI workflow for the repo's own tests

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: a `ci` check on every pull request and on pushes to `main` that runs every `.github/scripts/test-*.sh` and parses every workflow and `.packit.yaml` as YAML. Later tasks' tests run here with no other wiring.

- [ ] **Step 1: Write `ci.yml`.** Triggers `pull_request` and `push` to `main`; permissions `contents: read`; one job on `ubuntu-latest` with pinned `actions/checkout`. Steps: a loop `for t in .github/scripts/test-*.sh; do bash "$t"; done`; then `python3 - <<EOF` that loads each `.github/workflows/*.yml` and `.packit.yaml` with `yaml.safe_load`.
- [ ] **Step 2: Commit, push.** Expected on the PR: the `ci` check is green (`test-bump-spec.sh` runs now; later test scripts run automatically as they are added).

### Task 2: PR gate decision script

**Files:**
- Create: `.github/scripts/pr-gate.sh`
- Create: `.github/scripts/test-pr-gate.sh`
- Create: `.github/scripts/fixtures/` (JSON fixtures named in the tests)

**Interfaces:**
- Produces: `pr-gate.sh` reads a JSON array on stdin of objects `{name, status, conclusion, html_url, app}`; prints `pass`, `pending` or `fail` on the first line; for `fail` it then prints one `FAIL <name> <html_url>` line per failing check. Always exits 0. Considered checks: `app == "packit-as-a-service"` and name starts with `rpm-build:` but not `rpm-build:main:`. Package = last `:` field of the name.
- Rules: `pending` if there are no considered checks, any is not `completed`, or fewer than 3 distinct packages are present; else `fail` if any conclusion is not `success`; else `pass`.

- [ ] **Step 1: Write the failing test** `test-pr-gate.sh` with fixtures generated inline by `jq`/heredocs: (a) 12 `success` checks plus an `osh-diff-scan:...` `neutral` one gives first line `pass`; (b) 12 checks with one `in_progress` gives `pending`; (c) 9 `success` checks covering only 2 packages gives `pending`; (d) one `failure` (kmod, fedora-44) gives `fail` and a line `FAIL rpm-build:fedora-44-x86_64:facetimehd-kmod <url>`; (e) one `cancelled` gives `fail`; (f) all `rpm-build:main:...` checks `failure` with no PR checks gives `pending`; (g) a `failure` from another app slug is ignored (gives `pass` if the rest are green).
- [ ] **Step 2: Run it.** `bash .github/scripts/test-pr-gate.sh`. Expected: FAIL with `pr-gate.sh: No such file`.
- [ ] **Step 3: Implement `pr-gate.sh`** in bash with one `jq` program per the Interfaces rules.
- [ ] **Step 4: Run the test.** Expected: prints `PASS`, exit 0.
- [ ] **Step 5: Mutation check.** Temporarily change the package-count threshold from 3 to 1; the test must fail on (c). Restore it and rerun to `PASS`.
- [ ] **Step 6: Commit and push.**

### Task 3: Auto-merge workflow

**Files:**
- Create: `.github/workflows/bump-merge.yml`

**Interfaces:**
- Consumes: `pr-gate.sh` from Task 2.

- [ ] **Step 1: Write the workflow.** Trigger `check_run` types `[completed]`; job `if: github.event.check_run.app.slug == 'packit-as-a-service'`; `concurrency` group `bump-merge-${{ github.event.check_run.head_sha }}` with `cancel-in-progress: false`; permissions per Global Constraints. Steps: checkout `main`; list open PRs for the head SHA via `gh api repos/$GITHUB_REPOSITORY/commits/$SHA/pulls`, keep those whose `head.ref` matches `^(bump|revert)/` and whose `head.sha` equals `$SHA`; fetch all check runs for the SHA (`gh api --paginate .../check-runs --jq '.check_runs[] | {name,status,conclusion,html_url,app:.app.slug}'` piped to `jq -s`) and run `pr-gate.sh`. On `pending`, exit 0. On `fail`, post one PR comment listing the `FAIL` lines plus the run URL, guarded by a hidden marker `<!-- bump-gate:fail:$SHA -->` so reruns do not repeat it. On `pass`, `gh pr merge <n> --squash --delete-branch` and comment `Merged after all Packit builds passed: <run url>`.
- [ ] **Step 2: Validate.** `python3 -c "import yaml;yaml.safe_load(open('.github/workflows/bump-merge.yml'))"`; no output, exit 0. Also run `bash -n` on any inline script saved to a file, or extract and syntax-check the `run:` blocks.
- [ ] **Step 3: Commit and push.**
- [ ] **Step 4: Verify on the open PR.** The workflow runs from the default branch, so it first takes effect after the user merges the implementation PR. Record this in the PR description; the live check is Task 5.

### Task 4: Main watchdog

**Files:**
- Create: `.github/scripts/watchdog-decide.sh`
- Create: `.github/scripts/test-watchdog-decide.sh`
- Create: `.github/workflows/main-watchdog.yml`

**Interfaces:**
- Produces: `watchdog-decide.sh <changed-packages-csv>` reads the same JSON array on stdin; considered checks are Packit app checks named `rpm-build:main:*`. First line: `pending` (none considered, or any not completed), `ok` (no `failure` conclusions), `revert` (a check concluded `failure` for a package in the changed set) or `comment` (failures only in unchanged packages). Then one `FAIL <name> <html_url>` line per `failure`. Only the `failure` conclusion counts; `cancelled`, `timed_out`, `neutral` and `skipped` are ignored.

- [ ] **Step 1: Write the failing test** `test-watchdog-decide.sh`: (a) all 12 `rpm-build:main:*` green gives `ok`; (b) kmod `failure` with changed `facetimehd,facetimehd-kmod` gives `revert` and its `FAIL` line; (c) firmware `failure` with the same changed set gives `comment`; (d) kmod `cancelled` gives `ok`; (e) one check `in_progress` gives `pending`; (f) PR-style checks (`rpm-build:fedora-...`) are ignored, giving `pending`.
- [ ] **Step 2: Run it.** Expected: FAIL with `watchdog-decide.sh: No such file`.
- [ ] **Step 3: Implement `watchdog-decide.sh`.**
- [ ] **Step 4: Run the test.** Expected: `PASS`.
- [ ] **Step 5: Workflow `main-watchdog.yml`.** Trigger `check_run` completed; job `if: github.event.check_run.app.slug == 'packit-as-a-service' && startsWith(github.event.check_run.name, 'rpm-build:main:')`; concurrency per head SHA; checkout with `fetch-depth: 0`. Steps in order: exit unless the SHA is an ancestor of `origin/main`; find the merged PR through `gh api .../commits/$SHA/pulls` and exit unless its `head.ref` starts with `bump/`; compute the changed set from `git show --name-only --format= $SHA` (top-level directories among the three package dirs, joined by commas); gather checks and run `watchdog-decide.sh`. `pending`/`ok`: exit. `comment`: comment on the merged PR listing the `FAIL` lines, guarded by marker `<!-- watchdog:$SHA -->`. `revert`: unless `git ls-remote --heads origin revert/<sha7>` already shows the branch, configure the bot git identity, `git switch -c revert/<sha7>`, `git revert --no-edit $SHA`, push, and `gh pr create --base main` titled `Revert "<original title>"` with a body listing the `FAIL` lines, the original PR link and the run URL; also comment on the original PR with the same list and marker.
- [ ] **Step 6: Validate** the YAML as in Task 3.
- [ ] **Step 7: Commit and push.**

### Task 5: Docs and end-to-end verification

**Files:**
- Modify: `README.md` (Best practices list)

- [ ] **Step 1: README.** Add one bullet describing the flow (bump PR, Packit builds with a compile check, auto-merge on green, revert PR on a failed `main` build) and that `.github/workflows/bump-merge.yml` and `main-watchdog.yml` own it. Commit and push.
- [ ] **Step 2: Hand off for merge.** Tell the user the implementation PR is ready to merge; the workflows only take effect once on `main`. Do not merge it.
- [ ] **Step 3: After the user merges,** dispatch `upstream-bump.yml` on `main` and watch the open bump PR (currently PR #8, 0.7.2). Expected: its Packit builds rerun with the compile check; if all 12 are green the gate squash-merges it with a comment; if any is red the gate posts one comment listing the failing checks and does not merge.
- [ ] **Step 4: After a bump merges,** watch its `rpm-build:main:*` checks. Expected: `ok` (no action, no revert PR). Report the final state and any deviation to the user.
