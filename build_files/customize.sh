#!/usr/bin/bash
set -euo pipefail

KERNEL_VERSION="$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n')"
if [[ "$(wc -l <<<"${KERNEL_VERSION}")" -ne 1 ]]; then
    echo "Expected exactly one target kernel, found: ${KERNEL_VERSION}" >&2
    exit 1
fi

install -Dm0644 /ctx/repos/docker-ce.repo /etc/yum.repos.d/docker-ce.repo
cp -a /ctx/system_files/. /

source /etc/os-release
if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
    dnf5 install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${VERSION_ID}.noarch.rpm"
fi

dnf5 install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

dnf5 install -y \
    akmods \
    VirtualBox-kmodsrc \
    elfutils-libelf-devel \
    gcc \
    kmodtool \
    time \
    xz \
    "kernel-devel-${KERNEL_VERSION}"

akmod_dir="$(mktemp -d)"
dnf5 download --destdir "${akmod_dir}" akmod-VirtualBox
akmod_rpm="$(find "${akmod_dir}" -maxdepth 1 -name 'akmod-VirtualBox-*.rpm' -print -quit)"
test -n "${akmod_rpm}"
rpmkeys --checksig "${akmod_rpm}"

# RPM Fusion's current ostree post-install helper invokes akmodsbuild as root.
rpm -i --noscripts --nodeps "${akmod_rpm}"
dnf5 install -y VirtualBox VirtualBox-server
dnf5 check

systemd-sysusers
systemd-tmpfiles --create /usr/lib/tmpfiles.d/akmods.conf
systemctl enable bazzite-primary-user-groups.service
systemctl enable docker.socket

if systemctl list-unit-files vboxdrv.service --no-legend | grep -q '^vboxdrv.service'; then
    systemctl enable vboxdrv.service
fi

depmod -a "${KERNEL_VERSION}"
akmods --force --kernels "${KERNEL_VERSION}" --akmod VirtualBox
depmod -a "${KERNEL_VERSION}"

for module in vboxdrv vboxnetflt vboxnetadp; do
    path="$(modinfo -k "${KERNEL_VERSION}" -F filename "${module}")"
    vermagic="$(modinfo -k "${KERNEL_VERSION}" -F vermagic "${module}")"
    test -f "${path}"
    [[ "${vermagic}" == "${KERNEL_VERSION} "* ]]
done

dnf5 clean all
rm -rf \
    "${akmod_dir}" \
    /run/akmods \
    /run/dnf \
    /var/cache/akmods \
    /var/cache/dnf \
    /var/lib/dnf/system-repo.lock \
    /var/log/dnf5.log
