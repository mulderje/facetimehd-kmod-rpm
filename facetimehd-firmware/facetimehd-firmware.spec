%if 0%{?fedora}
%global debug_package %{nil}
%endif

%global srcname facetimehd

%global forgeurl https://github.com/patjak/%{srcname}-firmware
%global tag v1.0.0
%forgemeta

Name:           %{srcname}-firmware
Version:        1.0.0
Release:        1%{?dist}
Summary:        FacetimeHD firmware download and extraction tool

License:        GPL-2.0-only
URL:            %{forgeurl}
Source:         %{forgesource}

BuildArch:      noarch
ExclusiveArch:  x86_64

BuildRequires:  curl
BuildRequires:  cpio
BuildRequires:  gzip
BuildRequires:  make
BuildRequires:  xz

%description
FacetimeHD firmware download and extraction tool

%prep
%forgeautosetup

%build
# The Makefile downloads Apple's driver and hides curl errors (|| true), so retry a
# transient failure before failing the build.
for attempt in 1 2 3; do
    %make_build FW_DIR_BASE="%{_prefix}/lib/firmware" FW_DIR="%{_prefix}/lib/firmware/%{srcname}" && break
    [ "${attempt}" -eq 3 ] && exit 1
    echo "Firmware download/extract failed (attempt ${attempt}), retrying"
    sleep 15
done

%install
%make_install FW_DIR_BASE="%{_prefix}/lib/firmware" FW_DIR="%{_prefix}/lib/firmware/%{srcname}" 

%files
%license LICENSE
%{_prefix}/lib/firmware/facetimehd/firmware.bin

%changelog
* Sun Oct 25 2026 Jon Mulder <jon.e.mulder@gmail.com> - 1.0.0-1
- Restrict to x86_64 (driver and firmware are x86 only; no i686 kernels in Fedora)
- Retry the build-time driver download up to 3 times
- Drop unneeded p7zip BuildRequires (7z is only used for the unused DMG path); add xz for xzcat

* Sun Apr 19 2026 Jon Mulder <jon.e.mulder@gmail.com> - 1.0.0-1
- Mark package noarch; drop redundant bash/coreutils BuildRequires
- Ship upstream LICENSE via %%license macro

* Tue Mar 19 2024 Jon Mulder <jon.e.mulder@gmail.com>
- Updated upstream build and spec file to build
