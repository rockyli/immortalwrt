#!/usr/bin/env bash
# Validate the final system image on a disposable runner, without installing any APK.
set -euo pipefail
dest=$1
board=$2
work=$(mktemp -d)
root=$work/root
mkdir "$root"
cleanup() {
    if mountpoint -q "$root"; then sudo umount "$root" || return 1; fi
    rm -rf "$work"
}
trap cleanup EXIT
case "$board" in
    UFI001C_MB_V01) profile=ufi001c ;;
    UFI003C_MB_V02) profile=ufi003 ;;
    *) exit 1 ;;
esac
shopt -s nullglob
images=("$dest"/*-openstick-"$profile"-ext4-system.img)
manifests=("$dest"/*-openstick-"$profile".manifest)
[[ ${#images[@]} == 1 && ${#manifests[@]} == 1 ]]
simg2img "${images[0]}" "$work/system.ext4"
sudo mount -o loop,nodev,nosuid "$work/system.ext4" "$root"
[[ $(cat "$root/usr/share/ufi/pcb") == "$board" ]]

manifest_version() {
    awk -v p="$1" '$1 == p && $2 == "-" {v=$3; count++} END {if(count!=1) exit 1; print v}' "${manifests[0]}"
}
kernel=$(manifest_version kernel)
modules=(kmod-tun kmod-inet-diag kmod-nft-tproxy kmod-netlink-diag)
db="$root/lib/apk/db/installed"
check_installed() {
    awk -v pkg="$1" -v ver="$2" -v dep="$3" '
        BEGIN { RS=""; FS="\n" }
        {
            name=version=deps=""
            for(i=1;i<=NF;i++) {
                if ($i ~ /^P:/) name=substr($i,3)
                if ($i ~ /^V:/) version=substr($i,3)
                if ($i ~ /^D:/) deps=" " substr($i,3) " "
            }
            if (name==pkg && version==ver && (dep=="" || index(deps," " dep " "))) found++
        }
        END {exit found!=1}
    ' "$db" || { echo "Image database mismatch: $1 $2 $3" >&2; return 1; }
}
check_installed kernel "$kernel" ""
echo "$board installed kernel: $kernel"
for pkg in "${modules[@]}"; do
    version=$(manifest_version "$pkg")
    check_installed "$pkg" "$version" "kernel=$kernel"
    echo "$pkg $version requires kernel=$kernel (manifest and image DB verified)"
done

apk_name=luci-app-openclash-0.48.002.apk
curl --fail --location --retry 3 -o "$work/$apk_name" \
    "https://github.com/vernesong/OpenClash/releases/download/v0.48.002/$apk_name"
(cd "$work" && echo "f7ebbd43f9be15c5e6df26e5d0c03d50d0bb8f7fa4cc0d2c2bf048b08c0b155b  $apk_name" | sha256sum -c -)
sudo cp "$work/$apk_name" /usr/bin/qemu-aarch64-static "$root/tmp/"
sudo cp --remove-destination -L /etc/resolv.conf "$root/etc/resolv.conf"
apk=$(sudo find "$root" -type f -name apk -print -quit)
test -n "$apk"
guest_apk() { sudo chroot "$root" /tmp/qemu-aarch64-static "${apk#"$root"}" "$@"; }
cat "$root/etc/apk/repositories.d/distfeeds.list"
guest_apk --version
guest_apk update
for pkg in tree nano; do guest_apk add --simulate "$pkg"; done

# PSG v2.4.4 step 20 plus its Tailscale and LuCI stages. Pin the installed kernel ABI.
deps=(bash dnsmasq-full curl ca-bundle ip-full ruby ruby-yaml unzip luci-compat luci luci-base ss
      tailscale luci-app-tailscale-community)
guest_apk add --simulate --allow-untrusted "/tmp/$apk_name" "kernel=$kernel" "${modules[@]}" "${deps[@]}"
