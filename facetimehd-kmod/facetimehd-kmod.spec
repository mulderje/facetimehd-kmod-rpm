%if 0%{?fedora}
%global debug_package %{nil}
%endif

# akmod-only: kmodtool generates the akmod-facetimehd and kmod-facetimehd
# packages from the macro call below, so they are not defined by hand here.
# The other kmodtool modes (current, newest) need RPM Fusion's
# buildsys-build-<repo>-kerneldevpkgs and cannot be built on Copr.
%global buildforkernels akmod

%global srcname facetimehd
%global kmodname facetimehd

%global forgeurl https://github.com/patjak/%{srcname}
%global tag 0.7.0.1
%forgemeta

Name:       %{srcname}-kmod
Version:    %{tag}
Release:    1%{?dist}
Summary:    Kernel module for FacetimeHD webcam
License:    GPL-2.0-only
URL:        %{forgeurl}
Source:     %{forgesource}

Requires: facetimehd-firmware
# kernel bug? # "Cannot generate ORC metadata for CONFIG_UNWINDER_ORC=y"
# see https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=886474
BuildRequires:  elfutils-libelf-devel
BuildRequires:	gcc
BuildRequires:  rpmdevtools
BuildRequires:  kmodtool
# only the akmod SRPM build (e.g. Copr) needs kernel-devel, for the %%check compile test;
# akmods supplies it itself when it rebuilds with 'kernels' defined
%{!?kernels:BuildRequires: kernel-devel}


# Broadcom only provides x86_64 bits; Fedora no longer ships i686 kernels
ExclusiveArch:  x86_64


# kmodtool does its magic here
%{expand:%(kmodtool --target %{_target_cpu} --kmodname %{kmodname} %{?buildforkernels:--%{buildforkernels}} %{?kernels:--for-kernels "%{?kernels}"} 2>/dev/null) }


%description
Linux driver for the Facetime HD (Broadcom 1570) PCIe webcam found in recent
Macbooks.

%prep
# error out if there was something wrong with kmodtool
%{?kmodtool_check}

# print kmodtool output for debugging purposes:
kmodtool --target %{_target_cpu} --kmodname %{kmodname} %{?buildforkernels:--%{buildforkernels}} %{?kernels:--for-kernels "%{?kernels}"} 2>/dev/null | grep -v kmod-common

%forgeautosetup

pushd %{_builddir}

for kernel_version in %{?kernel_versions} ; do
 cp -a %{srcname}-%{version} _kmod_build_${kernel_version%%___*}
done

popd

%build
for kernel_version in %{?kernel_versions}; do
 pushd %{_builddir}/_kmod_build_${kernel_version%%___*}
 make -C ${kernel_version##*___} M=`pwd` modules
 popd
done

%install
for kernel_version in %{?kernel_versions}; do
 pushd %{_builddir}/_kmod_build_${kernel_version%%___*}
 mkdir -p ${RPM_BUILD_ROOT}%{kmodinstdir_prefix}${kernel_version%%___*}%{kmodinstdir_postfix}
 install -m 0755 *.ko ${RPM_BUILD_ROOT}%{kmodinstdir_prefix}${kernel_version%%___*}%{kmodinstdir_postfix}
 popd
done

# TODO: also /etc/modules-load.d/facetimehd.conf

chmod 0755 $RPM_BUILD_ROOT%{kmodinstdir_prefix}*%{kmodinstdir_postfix}/* || :
%{?akmod_install}

%check
# In akmod-only builds nothing above compiles the module, so compile it once against
# the newest kernel-devel in the buildroot to catch breakage early. Output is discarded.
# akmods' rebuild defines 'kernels' and compiles for real, so skip it there.
%if "%{?kernels}" == ""
kdir=$(ls -d %{_usrsrc}/kernels/*/ | sort -V | tail -n 1)
echo "Compile test against ${kdir}"
# rpm has already cd'd into the extracted source tree; nothing from here is installed
make -C "${kdir}" M="${PWD}" modules
%endif

%changelog
* Sun Oct 25 2026 Jon Mulder <jon.e.mulder@gmail.com> - 0.7.0.1-1
- Restrict to x86_64 (driver and firmware are x86 only; no i686 kernels in Fedora)
- Document akmod-only kmodtool usage and pass %%{kmodname} consistently
- Compile-test the module against the newest kernel-devel in %%check (akmod SRPM builds only)

* Sun Apr 19 2026 Jon Mulder <jon.e.mulder@gmail.com> - 0.7.0.1-1
- Update to 0.7.0.1 release (fixes build against kernel >= 7.0)
- Drop deprecated Group tag and stale --repo rpmfusion debug flag

* Mon Mar 17 2025 Jon Mulder <jon.e.mulder@gmail.com>
- Update to 0.6.13 release

* Tue Mar 19 2024 Jon Mulder <jon.e.mulder@gmail.com>
- Updated upstream build and spec file to build

* Tue Jul 26 2016 Ken Dreyer <kdreyer@redhat.com> 0-1
- Initial build.
