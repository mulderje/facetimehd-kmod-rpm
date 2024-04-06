# for some reason debug package does not work
%global debug_package %{nil}
# buildforkernels macro hint: when you build a new version or a new release
# that contains bugfixes or other improvements then you must disable the
# "buildforkernels newest" macro for just that build; immediately after
# queuing that build enable the macro again for subsequent builds; that way
# a new akmod package will only get build when a new one is actually needed
%global buildforkernels akmod

%global commitdate 20240322
%global commit b1f74242ad35f448bbac306f0087d289939290d9
%global shortcommit %(c=%{commit}; echo ${c:0:7})

%global srcname facetimehd
%global kmodname facetimehd


Name:       facetimehd-kmod
Version:    0.6.8
Release:    1.%{commitdate}git%{shortcommit}%{?dist}
Summary:    Kernel module for FacetimeHD webcam
Group:      System Environment/Kernel
License:    GPL-2.0-only
URL:        https://github.com/patjak/%{srcname}
Source:     https://github.com/patjak/%{srcname}/archive/%{commit}/%{srcname}-%{version}-%{shortcommit}.tar.gz

Requires: facetimehd-firmware
# kernel bug? # "Cannot generate ORC metadata for CONFIG_UNWINDER_ORC=y"
# see https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=886474
BuildRequires:  elfutils-libelf-devel
BuildRequires:	gcc
BuildRequires:  rpmdevtools
BuildRequires:  kmodtool
BuildRequires:  kernel-devel


# needed for plague to make sure it builds for i586 and i686
ExclusiveArch:  i686 x86_64
# ppc disabled because broadcom only provides x86 and x86_64 bits


# kmodtool does its magic here
%{expand:%(kmodtool --target %{_target_cpu} --kmodname %{name} %{?buildforkernels:--%{buildforkernels}} %{?kernels:--for-kernels "%{?kernels}"} 2>/dev/null) }


%description
Linux driver for the Facetime HD (Broadcom 1570) PCIe webcam found in recent
Macbooks.

%prep
# error out if there was something wrong with kmodtool
%{?kmodtool_check}

# print kmodtool output for debugging purposes:
kmodtool --target %{_target_cpu}  --repo rpmfusion --kmodname %{kmodname} %{?buildforkernels:--%{buildforkernels}} %{?kernels:--for-kernels "%{?kernels}"} 2>/dev/null | grep -v kmod-common

%autosetup -n %{srcname}-main -c

for kernel_version in %{?kernel_versions} ; do
 cp -a %{srcname}-%{commit} _kmod_build_${kernel_version%%___*}
done

%build
for kernel_version in %{?kernel_versions}; do
 pushd _kmod_build_${kernel_version%%___*}
 make -C ${kernel_version##*___} M=`pwd` modules
 popd
done

%install
for kernel_version in %{?kernel_versions}; do
 pushd _kmod_build_${kernel_version%%___*}
 mkdir -p ${RPM_BUILD_ROOT}%{kmodinstdir_prefix}${kernel_version%%___*}%{kmodinstdir_postfix}
 install -m 0755 *.ko ${RPM_BUILD_ROOT}%{kmodinstdir_prefix}${kernel_version%%___*}%{kmodinstdir_postfix}
 popd
done

# TODO: also /etc/modules-load.d/facetimehd.conf

chmod 0755 $RPM_BUILD_ROOT%{kmodinstdir_prefix}*%{kmodinstdir_postfix}/* || :
%{?akmod_install}

%changelog
* Tue Mar 19 2024 Jon Mulder <jon.e.mulder@gmail.com>
- Updated upstream build and spec file to build

* Tue Jul 26 2016 Ken Dreyer <kdreyer@redhat.com> 0-1
- Initial build.
