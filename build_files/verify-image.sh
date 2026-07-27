#!/usr/bin/bash
set -euo pipefail

IMAGE="${1:?Usage: verify-image.sh IMAGE}"

podman run --rm "${IMAGE}" /usr/bin/bash -euo pipefail -c '
KERNEL_VERSION="$(rpm -q kernel --queryformat "%{VERSION}-%{RELEASE}.%{ARCH}\n")"
[[ "$(wc -l <<<"${KERNEL_VERSION}")" -eq 1 ]]

rpm -q \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    VirtualBox \
    VirtualBox-server \
    VirtualBox-kmodsrc \
    akmod-VirtualBox

docker --version
docker compose version
docker buildx version
command -v VirtualBox
command -v VBoxManage
command -v VBoxHeadless

getent group docker
getent group vboxusers
systemctl is-enabled docker.socket
systemctl is-enabled bazzite-primary-user-groups.service
systemctl is-enabled vboxdrv.service
systemctl is-enabled virtualbox-extension-packs.service

unit_verify_output="$(systemd-analyze verify multi-user.target 2>&1)"
if grep -qi "ordering cycle" <<<"${unit_verify_output}"; then
    printf "%s\n" "${unit_verify_output}" >&2
    exit 1
fi

test -f /usr/lib/sysusers.d/bazzite-mt7927-docker-vbox.conf
test -x /usr/libexec/bazzite-configure-primary-user-groups
test -f /usr/lib/modules-load.d/virtualbox-host.conf
test -d /usr/lib64/virtualbox/ExtensionPacks
test -x /usr/libexec/bazzite-mount-virtualbox-extension-packs
test -f /usr/lib/systemd/system/virtualbox-extension-packs.service
test -f /usr/lib/tmpfiles.d/virtualbox-extension-packs.conf

if find /usr/lib64/virtualbox/ExtensionPacks -mindepth 1 -print -quit | grep -q .; then
    echo "VirtualBox Extension Packs must not be embedded" >&2
    exit 1
fi

for module in vboxdrv vboxnetflt vboxnetadp; do
    path="$(modinfo -k "${KERNEL_VERSION}" -F filename "${module}")"
    vermagic="$(modinfo -k "${KERNEL_VERSION}" -F vermagic "${module}")"
    test -f "${path}"
    [[ "${vermagic}" == "${KERNEL_VERSION} "* ]]
done

grep -q "vboxdrv" "/usr/lib/modules/${KERNEL_VERSION}/modules.dep"

mt7927_module="$(modinfo -k "${KERNEL_VERSION}" -F filename mt7925e)"
mt7927_vermagic="$(modinfo -k "${KERNEL_VERSION}" -F vermagic mt7925e)"
mt7927_aliases="$(modinfo -k "${KERNEL_VERSION}" -F alias mt7925e)"
test -f "${mt7927_module}"
[[ "${mt7927_vermagic}" == "${KERNEL_VERSION} "* ]]
grep -qi "7927" <<<"${mt7927_aliases}"

if rpm -qa | grep -Eqi "(oracle.*extension|virtualbox.*extpack)"; then
    echo "Oracle Extension Pack must not be embedded" >&2
    exit 1
fi

bootc container lint
'
