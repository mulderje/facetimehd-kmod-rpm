# Auto-merge for bump PRs, main watchdog, and a spec-level compile check

Date: 2026-10-25
Builds on: `2026-10-25-packit-copr-builds-design.md` (merged in PR #7)

## Goal

Upstream version bumps flow through without manual steps when they are safe, and are
rolled back with a clear message when they are not:

bump workflow opens a PR -> Packit builds it on Copr -> all builds pass -> PR is
squash-merged -> Packit builds `main` -> if those fail, a revert PR is opened and the
next daily bump retries.

Every failure path posts a message that says what failed and links to it.

## Findings behind the design

- Copr builds are akmod-only. In kmod build 11206062 the `%build` step is only
  `cd facetimehd-0.7.2` then exit 0: nothing is compiled. Green Packit checks therefore do
  not show that a new driver version builds against a kernel. Packit has no option to
  pass `--define kernels ...` to Copr.
- `akmodsbuild` (the user-side rebuild) runs `rpmbuild --rebuild <srpm> --define
  "kernels <uname -r>"` with no `--nocheck`. RPM Fusion specs guard build-only
  dependencies with `%{!?kernels: ...}`. `kmodtool` defines `kernel_versions` only for
  the per-kernel path.
- Packit reports builds on `main` commits as `rpm-build:main:<chroot>:<package>` check
  runs (15 check runs on `ddcbca0`), so a workflow can watch them. PR builds are
  `rpm-build:<chroot>:<package>`.
- `main` is not protected and repo auto-merge is off. Branch protection cannot be set from
  the automation, so merging is done by a workflow, not GitHub auto-merge.
- PRs opened with `GITHUB_TOKEN` do not start `pull_request` workflows, but do trigger
  Packit (verified on PR #8) and `check_run` workflows.

- OpenScanHub's scan for `facetimehd-firmware` fails because OSH builds the baseline
  SRPM in its own mock chroot (task 147139 under 147133) which has no network, so the
  firmware `%build` cannot download Apple's driver (`mv: cannot stat ...AppleCameraInterface`).
  Packit's `enable_net` does not reach it, and Packit exposes no OSH network option. The
  other two packages scan fine (kmod: no new findings).
- Upstream's `dkms.conf` carries `MODULES_CONF[0]="blacklist bdc_pci"`; none of our
  packages ship it. Fedora kernels do not build `bdc_pci` (`# CONFIG_USB_BDC_UDC is not set`),
  so it is a harmless safeguard for other kernels.
- The Makefile's `curl ... || true` hides download failures until the later `mv`. Every
  `main` build includes firmware, so one flaky Apple download could look like a bad driver
  bump to the watchdog.

## Design

### 1. Spec-level compile check (`facetimehd-kmod/facetimehd-kmod.spec`)

- Add `%{!?kernels:BuildRequires: kernel-devel}` in place of the unconditional
  `BuildRequires: kernel-devel`. `gcc` and `elfutils-libelf-devel` stay unconditional.
- Add a `%check` section that runs only when `kernels` is undefined (the akmod SRPM
  build on Copr/mock): copy the extracted source `%{srcname}-%{version}` to a scratch
  directory and run `make -C <newest directory in %{_usrsrc}/kernels> M=<scratch> modules`
  (newest by `sort -V`). Output is discarded; nothing is installed or shipped.
- The user-side `akmods` rebuild defines `kernels`, so the check and the extra
  BuildRequires do not apply there.
- A compile failure fails the Copr build, so Packit's PR and `main` checks become a real
  compile test on every Fedora target, including rawhide.

### 2. Auto-merge workflow (`.github/workflows/bump-merge.yml`)

- Trigger: `check_run` completed (and `workflow_dispatch` with a PR number for testing).
- Scope: open PRs whose head branch is `bump/*` or `revert/*`, opened by
  `github-actions[bot]`, matched by the check run's head SHA.
- Decision logic lives in `.github/scripts/pr-gate.sh` (pure function over the PR's check
  runs, unit-tested with fixture JSON):
  - Consider only check runs named `rpm-build:<chroot>:<package>` (not `rpm-build:main:`)
    from the Packit app. `osh-diff-scan:*` checks are ignored.
  - `pending`: any considered check not completed, or fewer than three distinct packages
    reported yet. Do nothing.
  - `fail`: any considered check concluded other than `success`. Post one PR comment
    (identified by a hidden marker so reruns do not repeat it) listing each failing check
    with its link. Do not merge.
  - `pass`: all considered checks `success`. Squash-merge the PR, delete the branch, and
    comment the merged commit.
- Permissions: `contents: write`, `pull-requests: write`.

### 3. Main watchdog (`.github/workflows/main-watchdog.yml`)

- Trigger: `check_run` completed, for check runs named `rpm-build:main:*` on a commit
  that is on `main`.
- Acts only on commits that came from a merged `bump/*` PR (found through the commit's
  associated PR). It never reverts a `revert/*` merge, so a failing revert cannot loop.
- Waits until every `rpm-build:main:*` check for that commit has completed (concurrency
  group per commit so only one run acts).
- If any concluded `failure`: create branch `revert/<short-sha>`, run `git revert` of
  the commit, and open a PR titled `Revert <original title>` whose body lists the failing
  checks with links and links the original PR. Also comment on the original (closed) PR
  with the same list. The revert PR is merged by workflow 2 once its builds pass.
- Only a `failure` conclusion triggers a revert (not `cancelled`, `timed_out` or
  `neutral`), to limit reverts caused by Copr outages.
- Failures are attributed by package (the last field of the check name). A revert happens
  only if a failing package is one the bump commit changed (its directory
  `facetimehd/`, `facetimehd-kmod/` or `facetimehd-firmware/` appears in the commit's
  changed files). Failures in untouched packages only produce a comment, so a flaky
  firmware download cannot revert a driver bump.
- Retry: GitHub cannot reopen a merged PR. The next daily run of `upstream-bump.yml`
  opens a fresh bump PR for the same tag, which must pass workflow 2's gate again. No
  skip list. A red bump PR just stays open.

### 4. Packaging additions

- `facetimehd/facetimehd.spec`: ship `/etc/modprobe.d/facetimehd.conf` containing
  `blacklist bdc_pci` (mode 0644, `%config(noreplace)`), created in `%install` like the
  existing `modules-load.d` file and listed explicitly in `%files`.
- `facetimehd-firmware/facetimehd-firmware.spec`: wrap the `make` call in `%build` in a
  3-attempt loop with a 15 second sleep between attempts; the build fails only if all
  attempts fail.
- `.packit.yaml`: set `osh_diff_scan_after_copr_build: false` on the firmware
  `pull_request` job only. The kmod and facetimehd scans stay on. The gate ignores all
  `osh-diff-scan:*` checks.

### 5. Messages

- Gate failure on a bump PR: PR comment (section 2).
- Main failure after merge: comment on the merged PR plus the revert PR (section 3).
- Successful merge: one short comment with the merged commit.
- All comments end with the link to the workflow run that produced them.

## Verification

- `pr-gate.sh` and `watchdog-decide.sh` get fixture tests: pending, fail, pass, osh neutral
  ignored, fewer than three packages, `main:` checks excluded, and for the watchdog
  package attribution (changed vs untouched package) and non-`failure` conclusions.
- Spec check: PR builds on Copr for all four Fedora targets. Prove it can fail by
  temporarily building a deliberately broken source change in a throwaway PR before
  relying on it (the check must go red, then green when reverted).
- PR #8 (0.7.2, currently open) is the first real subject: after the spec change lands on
  `main`, its next build must show the compile check running.
- End to end: dispatch `upstream-bump.yml`, watch the gate comment/merge, then confirm the
  `main` builds are watched.

## Risks and limits

- The compile check uses the newest `kernel-devel` in each Copr chroot, a proxy for what
  users get. A new rawhide kernel can turn builds red for reasons unrelated to a bump.
- Merge by workflow is not branch protection: a person can still push to `main`.
- A Copr outage that yields `failure` instead of `cancelled` can cause a pointless
  revert. The next daily bump repairs it.
- A passing compile check does not prove the camera works at runtime.

## Out of scope

- Enabling branch protection or GitHub auto-merge (needs repo admin).
- PR #5 and `kmodtool` patch testing.
- Changing the 12-check Packit matrix.
