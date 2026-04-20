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
  - [ ] Enable `pull_from_upstream` once the kmod is stable across kernel majors

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

### Building locally

```
$ git clone https://github.com/mulderje/facetimehd-kmod-rpm.git
$ cd facetimehd-kmod-rpm

$ rpmbuild -ba facetimehd*.spec --define "kernels $(uname -r)" --target $(uname -m)
$ rpmbuild -bs facetimehd*.spec --define "kernels $(uname -r)" --target $(uname -m)

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
