# SPDX-License-Identifier: GPL-2.0-only

# Factory reset uses fstools on the writable overlay. A firmware replacement
# on this experimental layout requires the matching pair of Fastboot images.
platform_check_image() {
	echo "UFI001C SquashFS: install boot.img and system.img with Fastboot." >&2
	return 74
}

platform_do_upgrade() {
	echo "UFI001C SquashFS: online upgrade is unavailable." >&2
	exit 1
}
