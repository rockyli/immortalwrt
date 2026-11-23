# SPDX-License-Identifier: GPL-2.0-only
REQUIRE_IMAGE_METADATA=1
RAMFS_COPY_BIN="$RAMFS_COPY_BIN sha256sum head"
RAMFS_COPY_DATA="$RAMFS_COPY_DATA /usr/share/ufi/pcb /usr/share/ufi/layout-v1"

ufi_match_layout() {
	local sys="$1" spec="$2" n label start sectors part
	while read -r n label start sectors; do
		part="$sys/mmcblk0p$n"
		grep -qx "PARTNAME=$label" "$part/uevent" &&
			[ "$(cat "$part/start")" = "$start" ] &&
			[ "$(cat "$part/size")" = "$sectors" ] || {
			echo "Unexpected eMMC partition p$n ($label)" >&2
			return 1
		}
	done < "$spec"
	set -- "$sys"/mmcblk0p*
	[ "$#" -eq 14 ]
}

ufi_identify() {
	[ "$(cat /usr/share/ufi/pcb)" = UFI001C_MB_V01 ] &&
		[ "$(cat /tmp/sysinfo/board_name)" = thwc,ufi001c ] &&
		grep -Eq '(^| )root=/dev/mmcblk0p14( |$)' /proc/cmdline &&
		[ -b /dev/mmcblk0p12 ] && [ -b /dev/mmcblk0p14 ] &&
		ufi_match_layout /sys/class/block /usr/share/ufi/layout-v1
}

ufi_get() { tar -xOf "$1" "$2"; }
ufi_hash() { sha256sum | cut -d' ' -f1; }

ufi_verify() (
	set -o pipefail
	local image="$1" pcb="$2" mode="$3" size members control raw
	size=$(wc -c < "$image") || return 1
	[ "$size" -le 167772160 ] || return 1
	fwtool -q -i /dev/null "$image" || return 1
	members=$(tar -tf "$image") || return 1
	[ "$members" = "$(printf '%s\n' CONTROL boot.img root.ext4.gz)" ] || return 1
	[ "$(tar -tvf "$image" | grep -c '^-')" = 3 ] || return 1
	control=$(ufi_get "$image" CONTROL) || return 1
	set -f
	set -- $control
	# format PCB kernel_bytes kernel_sha raw_bytes raw_sha gzip_sha
	[ "$#" = 7 ] && [ "$1" = UFI-EXT4-v1 ] && [ "$2" = "$pcb" ] &&
		[ "$5" = 1073741824 ] || return 1
	case "$3" in ''|*[!0-9]*) return 1;; esac
	[ "$3" -ge 2048 ] && [ "$3" -le 67108864 ] || return 1
	[ "$(ufi_get "$image" boot.img | wc -c)" -eq "$3" ] &&
		[ "$(ufi_get "$image" boot.img | ufi_hash)" = "$4" ] &&
		[ "$(ufi_get "$image" root.ext4.gz | ufi_hash)" = "$7" ] || return 1
	if [ "$mode" = full ]; then
		raw=$(ufi_get "$image" root.ext4.gz | gzip -dc | wc -c) || return 1
		[ "$raw" -eq "$5" ] &&
			[ "$(ufi_get "$image" root.ext4.gz | gzip -dc | ufi_hash)" = "$6" ] || return 1
	fi
)

platform_check_image() {
	ufi_identify && ufi_verify "$1" UFI001C_MB_V01 quick &&
		[ "$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)" -ge 49152 ] || return 74
}

platform_do_upgrade() {
	set -o pipefail
	local image="$1" mountdir=/tmp/ufi-newroot dev part control
	ufi_identify && ufi_verify "$image" UFI001C_MB_V01 full || exit 1
	awk '$2=="/" && $3=="tmpfs" {ok=1} END {exit !ok}' /proc/mounts || exit 1
	for part in mmcblk0p12 mmcblk0p14; do
		dev=$(cat "/sys/class/block/$part/dev") || exit 1
		awk -v dev="$dev" '$3==dev {busy=1} END {exit busy}' /proc/self/mountinfo || exit 1
		[ -z "$(ls -A "/sys/class/block/$part/holders")" ] || exit 1
	done
	[ "$(wc -l < /proc/swaps)" -eq 1 ] || exit 1
	if [ -n "$UPGRADE_BACKUP" ]; then
		gzip -t "$UPGRADE_BACKUP" && tar -tzf "$UPGRADE_BACKUP" >/dev/null || exit 1
	fi
	control=$(ufi_get "$image" CONTROL) || exit 1
	set -- $control
	ufi_get "$image" root.ext4.gz | gzip -dc | dd of=/dev/mmcblk0p14 bs=1M conv=fsync || exit 1
	[ "$(head -c "$5" /dev/mmcblk0p14 | ufi_hash)" = "$6" ] || exit 1
	if [ -n "$UPGRADE_BACKUP" ]; then
		mkdir -p "$mountdir" && mount -t ext4 /dev/mmcblk0p14 "$mountdir" &&
			cp "$UPGRADE_BACKUP" "$mountdir/sysupgrade.tgz" && sync && umount "$mountdir" || exit 1
	fi
	ufi_get "$image" boot.img | dd of=/dev/mmcblk0p12 bs=1M conv=fsync || exit 1
	[ "$(head -c "$3" /dev/mmcblk0p12 | ufi_hash)" = "$4" ] || exit 1
	sync
}
