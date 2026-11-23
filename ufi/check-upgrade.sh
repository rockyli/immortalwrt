#!/usr/bin/env bash
# Host-only checks; this script never opens a block device.
set -euo pipefail
image=$1
RAMFS_COPY_BIN= RAMFS_COPY_DATA=
. target/linux/msm89xx/ufi/platform.sh
spec=target/linux/msm89xx/ufi/layout-v1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
while read -r n label start sectors; do
    dir="$tmp/sys/mmcblk0p$n"
    mkdir -p "$dir"
    printf 'PARTNAME=%s\n' "$label" > "$dir/uevent"
    echo "$start" > "$dir/start"
    echo "$sectors" > "$dir/size"
done < "$spec"
ufi_match_layout "$tmp/sys" "$spec"
for field in start size uevent; do
    file="$tmp/sys/mmcblk0p14/$field"
    cp "$file" "$tmp/original"
    echo 'invalid' > "$file"
    if ufi_match_layout "$tmp/sys" "$spec"; then exit 1; fi
    cp "$tmp/original" "$file"
done
ufi_verify "$image" UFI001C_MB_V01 full
if ufi_verify "$image" UFI003C_MB_V02 quick; then exit 1; fi
head -c 4096 "$image" > "$tmp/truncated"
if ufi_verify "$tmp/truncated" UFI001C_MB_V01 quick; then exit 1; fi
mkdir "$tmp/payload"
tar -xf "$image" -C "$tmp/payload"
gzip -dc "$tmp/payload/root.ext4.gz" > "$tmp/ext4"
e2fsck -fn "$tmp/ext4"
test "$(debugfs -R 'cat /usr/share/ufi/pcb' "$tmp/ext4" 2>/dev/null)" = UFI001C_MB_V01
fwtool -i "$tmp/meta" "$image"
jq -e '.supported_devices | index("thwc,ufi001c") != null' "$tmp/meta"
printf x >> "$tmp/payload/boot.img"
tar -C "$tmp/payload" -cf "$tmp/corrupt" CONTROL boot.img root.ext4.gz
fwtool -I "$tmp/meta" "$tmp/corrupt"
if ufi_verify "$tmp/corrupt" UFI001C_MB_V01 quick; then exit 1; fi
echo "Passed payload integrity, ext4, board identity and partition layout tests."
