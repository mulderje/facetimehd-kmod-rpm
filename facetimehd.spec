%if 0%{?fedora}
%global debug_package %{nil}
%endif

%global commitdate 20240322
%global commit b1f74242ad35f448bbac306f0087d289939290d9
%global shortcommit %(c=%{commit}; echo ${c:0:7})

%global srcname facetimehd
%global kmodname facetimehd

Name:       facetimehd
Version:    0.6.8
Release:    1.%{commitdate}git%{shortcommit}%{?dist}
Summary:    Kernel module for FacetimeHD webcam
Group:      System Environment/Kernel
License:    GPL-2.0-only
URL:        https://github.com/patjak/%{srcname}
Source:     https://github.com/patjak/%{srcname}/archive/%{commit}/%{srcname}-%{version}-%{shortcommit}.tar.gz

Provides: %{name}-kmod-common = %{version}
Requires: %{name}-kmod >= %{version}

Requires: %{name}-firmware

%description
Linux driver for the Facetime HD (Broadcom 1570) PCIe webcam found in recent
Macbooks.

%prep
%autosetup -c %{name}-main -p1

#pwd
#tree

# Below files section taken from https://github.com/frgt10/facetimehd-dkms/blob/master/facetimehd-dkms.spec
%install
if [ "$RPM_BUILD_ROOT" != "/" ]; then
	rm -rf $RPM_BUILD_ROOT
fi

mkdir -p $RPM_BUILD_ROOT/usr/src/%{name}-%{version}/
cp -rf %{srcname}-%{commit}/* $RPM_BUILD_ROOT/usr/src/%{name}-%{version}/

mkdir -p $RPM_BUILD_ROOT/usr/share/doc/%{name}/
cp %{srcname}-%{commit}/README.md $RPM_BUILD_ROOT/usr/share/doc/%{name}/

mkdir -p $RPM_BUILD_ROOT/etc/modules-load.d/
echo -e "# Load facetimehd.ko at boot\nfacetimehd" > $RPM_BUILD_ROOT/etc/modules-load.d/facetimehd.conf

#pwd
#tree

#tree $RPM_BUILD_ROOT
#tree %{_builddir}
#tree %{buildroot}

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
