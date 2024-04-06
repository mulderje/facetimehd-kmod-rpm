%if 0%{?fedora}
%global debug_package %{nil}
%endif

%global srcname facetimehd

%global forgeurl https://github.com/patjak/%{srcname}
%global tag 0.6.8.1
%forgemeta

Name:       facetimehd
Version:	0.6.8.1
Release:    1%{?dist}
Summary:    Kernel module for FacetimeHD webcam
Group:      System Environment/Kernel
License:    GPL-2.0-only
URL:        %{forgeurl}
Source:     %{forgesource}

Provides: %{name}-kmod-common = %{version}
Requires: %{name}-kmod >= %{version}

Requires: %{name}-firmware

%description
Linux driver for the Facetime HD (Broadcom 1570) PCIe webcam found in recent
Macbooks.

%prep
%forgeautosetup

%install
if [ "$RPM_BUILD_ROOT" != "/" ]; then
	rm -rf $RPM_BUILD_ROOT
fi

mkdir -p $RPM_BUILD_ROOT/usr/src/%{name}-%{version}/
cp -rf %{_builddir}/%{srcname}-%{version}/* $RPM_BUILD_ROOT/usr/src/%{name}-%{version}

mkdir -p $RPM_BUILD_ROOT/usr/share/doc/%{name}/
cp %{_builddir}/%{srcname}-%{version}/README.md $RPM_BUILD_ROOT/usr/share/doc/%{name}/

mkdir -p $RPM_BUILD_ROOT/etc/modules-load.d/
echo -e "# Load facetimehd.ko at boot\nfacetimehd" > $RPM_BUILD_ROOT/etc/modules-load.d/facetimehd.conf

%clean
if [ "$RPM_BUILD_ROOT" != "/" ]; then
	rm -rf $RPM_BUILD_ROOT
fi

%files
#%doc openrgb-dkms-main/README.md
#%license openrgb-dkms-main/LICENSE
%defattr(-,root,root)
%config /etc/modules-load.d/facetimehd.conf
/usr/src/%{name}-%{version}/
/usr/share/doc/%{name}/

%changelog
* Tue Mar 19 2024 Jon Mulder <jon.e.mulder@gmail.com>
- Updated upstream build and spec file to build
