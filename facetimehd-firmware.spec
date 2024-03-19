%global debug_package %{nil}

%global forgeurl https://github.com/patjak/facetimehd-firmware
%global branch master
%forgemeta

%global srcname facetimehd

Name:           %{srcname}-firmware
Version:        0.1
Release:        1%{?dist}
Summary:        FacetimeHD firmware download and extraction tool

License:        GPLv2 
URL:		%{forgeurl}
Source:		%{forgesource}

BuildRequires:  bash
BuildRequires:  coreutils
BuildRequires:  curl
BuildRequires:  cpio
BuildRequires:  gzip
BuildRequires:  make
BuildRequires:  p7zip

Requires:       bash

%description
FacetimeHD firmware download and extraction tool

%prep
%forgeautosetup -v
# %forgeautosetup -v
# No -c for forgeautosetup. Need something like other specs
# Break out forgesetup/autosetup

%build
%make_build FW_DIR_BASE="%{_prefix}/lib/firmware" FW_DIR="%{_prefix}/lib/firmware/%{srcname}" 

%install
%make_install FW_DIR_BASE="%{_prefix}/lib/firmware" FW_DIR="%{_prefix}/lib/firmware/%{srcname}" 

%files
#%license LICENSE
#%doc README.md
%{_prefix}/lib/firmware/facetimehd/firmware.bin

%changelog
* Tue Mar 19 2024 Jon Mulder <jon.e.mulder@gmail.com>
- Updated upstream build and spec file to build