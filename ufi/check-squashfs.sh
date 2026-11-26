#!/usr/bin/env bash
# Verify the UFI001C Fastboot image pair without attaching a device.
set -euo pipefail
dest=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
shopt -s nullglob
boot=("$dest"/*-openstick-ufi001c-squashfs-boot.img)
system=("$dest"/*-openstick-ufi001c-squashfs-system.img)
kernels=(build_dir/target-*/linux-msm89xx_msm8916/linux-*/scripts/extract-ikconfig)
[[ ${#boot[@]} == 1 && ${#system[@]} == 1 && ${#kernels[@]} == 1 ]]
layout=target/linux/msm89xx/ufi/layout-v1
[[ $(stat -c %s "${boot[0]}") -le $(awk '$2=="boot" {print $4*512}' "$layout") ]]
python3 "$RUNNER_TEMP/android-boot-tools/unpack_bootimg.py" --boot_img "${boot[0]}" --out "$work/boot" > "$work/header"
grep -F 'root=/dev/mmcblk0p14 rootfstype=squashfs ro rootwait' "$work/header"
"${kernels[0]}" "$work/boot/kernel" > "$dest/kernel.config"
for symbol in SQUASHFS SQUASHFS_XZ OVERLAY_FS F2FS_FS F2FS_FS_XATTR BLK_DEV_LOOP; do
    grep -Fx "CONFIG_$symbol=y" "$dest/kernel.config"
done

simg2img "${system[0]}" "$work/system.raw"
python3 - "$work/system.raw" "$layout" <<'PY'
import os
import struct
import sys

image, layout = sys.argv[1:]
with open(layout) as table:
    sectors, = (int(row[3]) for row in map(str.split, table) if row[:2] == ["14", "rootfs"])
with open(image, "rb") as root:
    header = root.read(96)
    if header[:4] != b"hsqs" or struct.unpack_from("<H", header, 20)[0] != 4:
        sys.exit("Fastboot rootfs must begin with XZ SquashFS")
    used, = struct.unpack_from("<Q", header, 40)
    offset = (used + 65535) & ~65535
    if used < len(header) or os.fstat(root.fileno()).st_size != offset + 4096:
        sys.exit("SquashFS end or rootfs_data alignment is invalid")
    root.seek(offset)
    if root.read() != bytes.fromhex("deadc0de") + bytes(4092):
        sys.exit("Missing factory overlay initialization block")
    # fstools selects F2FS on a tail larger than 100 MiB.
    if sectors * 512 - offset <= 100 * 1024**2:
        sys.exit("Insufficient p14 space for the F2FS overlay")
    print(f"SquashFS uses {used} bytes; rootfs_data starts at {offset} in p14")
PY
