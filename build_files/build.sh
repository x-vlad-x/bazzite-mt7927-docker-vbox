#!/bin/bash
set -ouex pipefail

CTX="/ctx"
BUILD_DIR="/tmp/mt7927-build"
OUTPUT_DIR="/output"
FIRMWARE_DIR="/usr/lib/firmware/mediatek/mt7927"
BT_FIRMWARE="BT_RAM_CODE_MT6639_2_1_hdr.bin"
WIFI_FIRMWARE=("WIFI_MT6639_PATCH_MCU_2_1_hdr.bin" "WIFI_RAM_CODE_MT6639_2_1.bin")

### Kernel version detection
KVER=$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' | tail -1)
echo "Preparing MT7927 support for kernel: ${KVER}"

### Upstream detection
# The three pieces of MT7927 support land independently: the WiFi PCI ID in
# mt7925e, the MT6639 variant in btmtk, and the MT6639 Bluetooth firmware,
# which linux-firmware does not ship at all. Probe them separately - a single
# guard keyed on the WiFi ID silently drops Bluetooth the moment the WiFi half
# goes mainline, which is exactly what happened on kernel 7.2.4.
firmware_present() {
    local name="$1" ext
    for ext in "" ".xz" ".zst" ".gz"; do
        if [ -e "${FIRMWARE_DIR}/${name}${ext}" ]; then
            return 0
        fi
    done
    return 1
}

wifi_upstream=false
bt_upstream=false
if modinfo -k "${KVER}" -F alias mt7925e 2>/dev/null | grep -q '7927'; then
    wifi_upstream=true
fi
if modinfo -k "${KVER}" -F firmware btmtk 2>/dev/null | grep -q "mt7927/${BT_FIRMWARE}"; then
    bt_upstream=true
fi

missing_firmware=()
for fw in "${BT_FIRMWARE}" "${WIFI_FIRMWARE[@]}"; do
    if ! firmware_present "${fw}"; then
        missing_firmware+=("${fw}")
    fi
done

build_modules=true
if "${wifi_upstream}" && "${bt_upstream}"; then
    build_modules=false
fi

echo "Upstream status for ${KVER}: wifi=${wifi_upstream} bluetooth=${bt_upstream}"
echo "Firmware missing from the base image: ${missing_firmware[*]:-none}"

if [ "${build_modules}" = false ] && [ "${#missing_firmware[@]}" -eq 0 ]; then
    echo "MT7927 drivers and firmware already present in ${KVER}, skipping."
    mkdir -p "${OUTPUT_DIR}"
    exit 0
fi

### Prepare sources using submodule Makefile
mkdir -p "${BUILD_DIR}"
DKMS="${BUILD_DIR}/dkms"
cp -r "${CTX}/mediatek-mt7927-dkms" "${DKMS}"

if [ "${build_modules}" = true ]; then
    ### Install build dependencies
    dnf5 install -y --skip-unavailable \
        gcc make "kernel-devel-${KVER}" kernel-headers python3 curl patch xz unzip

    make -C "${DKMS}" download
    make -C "${DKMS}" sources

    SRCDIR="${DKMS}/_build"
    FIRMWARE_SRC="${SRCDIR}/firmware"

    ### Compile
    KSRC="/lib/modules/${KVER}/build"
    make -C "${KSRC}" M="${SRCDIR}/bluetooth" -j"$(nproc)" modules
    make -C "${KSRC}" M="${SRCDIR}/mt76"      -j"$(nproc)" modules

    ### Stage kernel modules
    INSTALL_DIR="${OUTPUT_DIR}/usr/lib/modules/${KVER}/extra/mt7927"
    mkdir -p "${INSTALL_DIR}"
    install -m644 "${SRCDIR}"/bluetooth/{btusb,btmtk}.ko                          "${INSTALL_DIR}/"
    install -m644 "${SRCDIR}"/mt76/{mt76,mt76-connac-lib,mt792x-lib}.ko           "${INSTALL_DIR}/"
    install -m644 "${SRCDIR}"/mt76/mt7921/{mt7921-common,mt7921e}.ko              "${INSTALL_DIR}/"
    install -m644 "${SRCDIR}"/mt76/mt7925/{mt7925-common,mt7925e}.ko              "${INSTALL_DIR}/"
    xz --check=crc32 -f "${INSTALL_DIR}"/*.ko

    ### Out-of-tree modules have to win over the stock kernel ones
    install -Dm644 "${CTX}/config/depmod-mt7927.conf" "${OUTPUT_DIR}/etc/depmod.d/mt7927.conf"
else
    ### Drivers are upstream, only the vendor firmware blobs are still needed.
    ### Skip the kernel tarball and go straight for the MediaTek driver ZIP.
    echo "MT7927 drivers are upstream in ${KVER}, extracting firmware only."
    dnf5 install -y --skip-unavailable python3 curl xz unzip

    FIRMWARE_SRC="${BUILD_DIR}/firmware"
    mkdir -p "${FIRMWARE_SRC}"
    "${DKMS}/download-driver.sh" "${BUILD_DIR}"
    DRIVER_ZIP=$(find "${BUILD_DIR}" -maxdepth 1 -name 'DRV_WiFi_MTK_MT7925_MT7927*.zip' | head -1)
    if [ -z "${DRIVER_ZIP}" ]; then
        echo >&2 "ERROR: MediaTek driver ZIP not found after download"
        exit 1
    fi
    python3 "${DKMS}/extract_firmware.py" "${DRIVER_ZIP}" "${FIRMWARE_SRC}"
fi

### Stage the firmware the base image does not ship
for fw in "${missing_firmware[@]}"; do
    install -Dm644 "${FIRMWARE_SRC}/${fw}" "${OUTPUT_DIR}${FIRMWARE_DIR}/${fw}"
done

### Stage config files
mkdir -p "${OUTPUT_DIR}/etc/modules-load.d"
echo "mt7925e" > "${OUTPUT_DIR}/etc/modules-load.d/mt7925e.conf"

echo "MT7927 preparation complete."
