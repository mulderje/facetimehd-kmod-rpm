# facetimehd-kmod
Spec files for building kernel module for [patjak/facetimehd](https://github.com/patjak/facetimehd/). 

**WARNING: this is a WIP to get the driver working on an old MacBookAir6,2. These are my first spec files, but they are building are working for me locally. This is provided as is. Contributions and suggestions for improvements  welcome.**

Build process / TODOs:

- [x] Initially forked from [ktdreyer/facetimehd-kmod-rpm](https://github.com/ktdreyer/facetimehd-kmod-rpm)
- [x] Update specs:
  - [x] Remove rpmfusion
  - [x] Update to latest git revs
  - [x] Add spec for facetimehd-firmware
  - [ ] Consolidate facetimehd-firmware into main spec?
- [x] Copr created and builds
- [ ] Contribut to ublue (WIP: ublue-os/akmods#163)
- [x] Best practices: [Packit](https://packit.dev) drives Copr builds (PR scratch + main)
  - [x] New upstream tags open bump PRs via `.github/workflows/upstream-bump.yml` (Packit's release jobs only target Fedora dist-git, so they are not used here)
  - Packit builds each PR in [mulderje/facetimehd-kmod-pr](https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod-pr/) and each push to `main` in [mulderje/facetimehd-kmod](https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod/)
  - Bump PRs merge themselves once all Packit builds pass (`.github/workflows/bump-merge.yml`). The kmod build compiles the driver against the newest `kernel-devel` in `%check`, so a green build means it compiles. If the `main` builds of a bump fail, `.github/workflows/main-watchdog.yml` opens a revert PR and comments why; the next daily bump retries

## Automation

- `upstream-bump.yml` checks for new upstream tags daily and drives each bump from start to finish in one run: it opens the PR, waits for Packit's PR builds, merges when they are green (a red one gets a comment, a `needs-review` label and a review request to the owner), waits for the builds of the merge commit on `main`, opens a revert PR (review requested) if a package the bump changed fails, and comments the outcome on the PR. The run turns red whenever a person needs to look, so GitHub emails the owner. Its manual `force` option opens a changelog-only PR to test the pipeline.
- The daily bump run first sweeps leftovers (open green bot PRs, recent bump commits on `main`), so anything an earlier run dropped is picked up within a day. `bump-merge.yml` and `main-watchdog.yml` do the same merging and reverting as a safety net, triggered by Packit check events and by an `upstream-bump` run that fails, is cancelled or times out. They do not poll. GitHub does not deliver check events for PRs opened with the workflow token, which is why the bump run waits for Packit itself.
- `kernel-drift.yml` compiles the driver against the newest `kernel-devel` of Fedora 43, 44, 45 and rawhide every week; a failure means a new kernel broke it and upstream needs a fix.
- `keepalive.yml` re-enables the scheduled workflows monthly so GitHub's 60-day inactivity rule does not switch them off.

## Commit sign-off

Every squash-merged commit on `main` carries a `Signed-off-by:` trailer. GitHub makes the squash commit with the PR author as author and signs it itself (Verified); the auto-merge workflow adds the trailer, and manual squash merges should include it (or set the repo's default squash message to the PR title and description, which carry it).

## Known issues and follow-ups

- The OpenScanHub diff scan for `facetimehd-firmware` ends neutral on rawhide: OSH builds the baseline SRPM in a chroot without network, and the firmware's `%build` downloads Apple's driver. It is harmless (the auto-merge gate ignores `osh-diff-scan:*`); a fix is still to be found. (Issues are disabled on this repo, so it is tracked here.)
- Copr's FedoraReview step reports "No disttag found" for `facetimehd-kmod` because `kmodtool` names the binary packages `akmod-facetimehd` and `kmod-facetimehd`, not after the source package. It does not fail the build and is a Copr project setting.
- The driver optionally loads sensor calibration "set files" (`facetimehd/NNNN_01XX.dat`). They are not packaged: `facetimehd-firmware` v1.0.0 does not provide them, and upstream `master` (firmware 5.60.0 plus all eleven set files) has no release tag yet.
- The calibration set files above, and firmware 5.60.0, wait on an upstream release tag. Requested in [patjak/facetimehd-firmware#17](https://github.com/patjak/facetimehd-firmware/issues/17); bump PRs will follow once a tag exists.
- `bump-merge.yml` and `main-watchdog.yml` have been tested with fixtures but have not run on a real bump yet; the first upstream tag after 0.7.2 will be their first live run.

## Copr Build

Package | Build Status
------- | ------------
facetimehd | [![badge](https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod/package/facetimehd/status_image/last_build.png)](https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod/package/facetimehd/)
facetimehd-kmod | [![badge](https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod/package/facetimehd-kmod/status_image/last_build.png)](https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod/package/facetimehd-kmod/)
facetimehd-firmware | [![badge](https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod/package/facetimehd-firmware/status_image/last_build.png)](https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod/package/facetimehd-firmware/)


## Using `facetimehd-kmod` spec files

To install, add the [mulderje/facetimehd-kmod](https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod/) COPR and install `facetimehd-kmod` via `dnf` or `rpm-ostree`.

### Add copr and install with `rpm-ostree`

```
$ sudo wget "https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod/repo/fedora-$(rpm -E %fedora)/mulderje-facetimehd-kmod-fedora-$(rpm -E %fedora).repo" -O /etc/yum.repos.d/_copr_mulderje-facetimehd-kmod.repo
$ sudo rpm-ostree install facetimehd-kmod facetimehd-firmware
```

### Repo layout

Each package lives in its own subdirectory so Packit/Copr can build them
independently (see `.packit.yaml`):

```
facetimehd/           facetimehd.spec
facetimehd-kmod/      facetimehd-kmod.spec
facetimehd-firmware/  facetimehd-firmware.spec
```

### Building locally

```
$ git clone https://github.com/mulderje/facetimehd-kmod-rpm.git
$ cd facetimehd-kmod-rpm

$ rpmbuild -ba */*.spec --define "kernels $(uname -r)" --target $(uname -m)
$ rpmbuild -bs */*.spec --define "kernels $(uname -r)" --target $(uname -m)

$ mkdir -p /tmp/mockbuild
$ mock --enable-network -r fedora-rawhide-x86_64 --rebuild --resultdir=/tmp/mockbuild/ ~/rpmbuild/SRPMS/facetimehd-*.src.rpm
$ sudo rpm-ostree install ...
```

## Development workflow

Copr builds are driven by [Packit](https://packit.dev) via `.packit.yaml` in
the repo root. Two flows:

| Trigger | Copr project | Targets | Purpose |
|---|---|---|---|
| Pull request | [`mulderje/facetimehd-kmod-pr`](https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod-pr/) | `fedora-all-x86_64` | Per-PR scratch build across every active Fedora release plus rawhide, so rawhide breakage is caught before merge. Packit posts the build link as a commit status. |
| Push to `main` | [`mulderje/facetimehd-kmod`](https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod/) | `fedora-stable-x86_64` | Official build consumed by downstream images (e.g. ublue-oldair). Stable releases only — rawhide users can pull from the PR Copr. |

Both flows build all three packages (`facetimehd`, `facetimehd-kmod`,
`facetimehd-firmware`). Targets use [Packit aliases](https://packit.dev/docs/configuration/#aliases)
so the matrix tracks Fedora's lifecycle automatically — no config bump
when a new release branches or an old one goes EOL.

### One-time setup

1. Install the [Packit GitHub App](https://github.com/apps/packit-as-a-service)
   on this repository.
2. Create the scratch Copr project `mulderje/facetimehd-kmod-pr` with the
   same chroots as the official project.
3. In both Copr projects' **Settings → Permissions**, grant the
   `packit` user `builder` access.
4. If a GitHub → Copr webhook was previously wired directly on this repo,
   disable it to avoid double-builds — Packit now owns the `main` trigger.
