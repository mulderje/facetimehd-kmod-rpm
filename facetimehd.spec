%if 0%{?fedora}
%global debug_package %{nil}
%endif

%global srcname facetimehd

%global forgeurl https://github.com/patjak/%{srcname}
%global tag 0.7.0.1
%forgemeta

Name:       facetimehd
Version:    %{tag}
Release:    1%{?dist}
Summary:    Kernel module for FacetimeHD webcam
License:    GPL-2.0-only
URL:        %{forgeurl}
Source:     %{forgesource}

BuildArch:  noarch

Provides: %{name}-kmod-common = %{version}
Requires: %{name}-kmod >= %{version}

Requires: %{name}-firmware

%description
Linux driver for the Facetime HD (Broadcom 1570) PCIe webcam found in recent
Macbooks.

%prep
%forgeautosetup

%install
install -d -m 0755 %{buildroot}%{_sysconfdir}/modules-load.d
install -p -m 0644 /dev/stdin %{buildroot}%{_sysconfdir}/modules-load.d/facetimehd.conf <<'EOF'
# Load facetimehd.ko at boot
facetimehd
EOF

%files
%license LICENSE
%doc README.md
%config(noreplace) %{_sysconfdir}/modules-load.d/facetimehd.conf

%changelog
* Sun Apr 19 2026 Jon Mulder <jon.e.mulder@gmail.com> - 0.7.0.1-1
- Update to 0.7.0.1 release (fixes build against kernel >= 7.0)
- Package upstream LICENSE and README.md via %%license/%%doc macros
- Mark package noarch; drop deprecated Group tag and legacy %%clean cruft
- Drop unused DKMS source tree under /usr/src

* Mon Mar 17 2025 Jon Mulder <jon.e.mulder@gmail.com>
- Update to 0.6.13 release

* Tue Mar 19 2024 Jon Mulder <jon.e.mulder@gmail.com>
- Updated upstream build and spec file to build
