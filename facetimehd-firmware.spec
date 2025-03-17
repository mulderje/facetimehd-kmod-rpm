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

BuildRequires:  bash
BuildRequires:  coreutils
BuildRequires:  curl
BuildRequires:  cpio
BuildRequires:  gzip
BuildRequires:  make
BuildRequires:  p7zip

%description
FacetimeHD firmware download and extraction tool

%prep
%forgeautosetup

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
