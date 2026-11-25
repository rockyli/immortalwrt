#!/usr/bin/env bash
# Host-only checks; this script never opens a block device.
set -euo pipefail
image=$1
RAMFS_COPY_BIN= RAMFS_COPY_DATA=
. target/linux/msm89xx/ufi/platform.sh
pcb=$2
layouts=target/linux/msm89xx/ufi
case "$pcb" in
    UFI001C_MB_V01) other=UFI003C_MB_V02; spec=$layouts/layout-v1; wrong=$layouts/layout-ufi003c-v1 ;;
    UFI003C_MB_V02) other=UFI001C_MB_V01; spec=$layouts/layout-ufi003c-v1; wrong=$layouts/layout-v1 ;;
    *) exit 1 ;;
esac
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
if ufi_match_layout "$tmp/sys" "$wrong"; then exit 1; fi
for field in start size uevent; do
    file="$tmp/sys/mmcblk0p14/$field"
    cp "$file" "$tmp/original"
    echo 'invalid' > "$file"
    if ufi_match_layout "$tmp/sys" "$spec"; then exit 1; fi
    cp "$tmp/original" "$file"
done
ufi_verify "$image" "$pcb" full
if ufi_verify "$image" "$other" quick; then exit 1; fi
head -c 4096 "$image" > "$tmp/truncated"
if ufi_verify "$tmp/truncated" "$pcb" quick; then exit 1; fi
mkdir "$tmp/payload"
tar -xf "$image" -C "$tmp/payload"
gzip -dc "$tmp/payload/root.ext4.gz" > "$tmp/ext4"
e2fsck -fn "$tmp/ext4"
test "$(debugfs -R 'cat /usr/share/ufi/pcb' "$tmp/ext4" 2>/dev/null)" = "$pcb"
debugfs -R 'cat /usr/share/ufi/layout-v1' "$tmp/ext4" 2>/dev/null | cmp - "$spec"
debugfs -R 'cat /etc/board.d/99-ufi-network' "$tmp/ext4" 2>/dev/null | cmp - "$layouts/99-ufi-network"
debugfs -R 'cat /etc/config/dhcp' "$tmp/ext4" 2>/dev/null | awk '
    $1 == "config" { lan = ($2 == "dhcp" && $3 == "lan") }
    lan && $1 == "option" && $2 == "start" { start = $3 }
    lan && $1 == "option" && $2 == "limit" { limit = $3 }
    END { exit !(start == 100 && limit == 150) }
'
fwtool -i "$tmp/meta" "$image"
jq -e '.supported_devices | index("thwc,ufi001c") != null' "$tmp/meta"
printf x >> "$tmp/payload/boot.img"
tar -C "$tmp/payload" -cf "$tmp/corrupt" CONTROL boot.img root.ext4.gz
fwtool -I "$tmp/meta" "$tmp/corrupt"
if ufi_verify "$tmp/corrupt" "$pcb" quick; then exit 1; fi
echo "Passed payload integrity, ext4, board identity and partition layout tests."
