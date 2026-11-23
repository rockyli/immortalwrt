#!/usr/bin/env bash
set -euo pipefail
boot=$1
root=$2
out=$3
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$boot" "$tmp/boot.img"
cp --sparse=always "$root" "$tmp/root.ext4"
cd "$tmp"
rc=0
e2fsck -fy root.ext4 || rc=$?
(( rc == 0 || rc == 1 ))
e2fsck -fn root.ext4
test "$(stat -c %s root.ext4)" = 1073741824
test "$(head -c 8 boot.img)" = 'ANDROID!'
gzip -nc root.ext4 > root.ext4.gz
hash() { sha256sum "$1" | cut -d' ' -f1; }
printf 'UFI-EXT4-v1 UFI001C_MB_V01 %s %s %s %s %s\n' \
    "$(stat -c %s boot.img)" "$(hash boot.img)" "$(stat -c %s root.ext4)" \
    "$(hash root.ext4)" "$(hash root.ext4.gz)" > CONTROL
tar --format=ustar --owner=0 --group=0 --mtime="@${SOURCE_DATE_EPOCH:-0}" \
    -cf "$out.new" CONTROL boot.img root.ext4.gz
mv "$out.new" "$out"
