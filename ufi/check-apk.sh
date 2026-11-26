#!/usr/bin/env bash
# Validate the final system image and its PSG dependencies on a disposable, unpacked image copy.
set -euo pipefail
dest=$1
board=$2
filesystem=${3:-ext4}
work=$(mktemp -d)
root=$work/root
mkdir "$root"
cleanup() {
    if mountpoint -q "$root"; then sudo umount "$root" || return 1; fi
    sudo rm -rf -- "$work"
}
trap cleanup EXIT
case "$board" in
    UFI001C_MB_V01) profile=ufi001c ;;
    UFI003C_MB_V02) profile=ufi003 ;;
    *) exit 1 ;;
esac
shopt -s nullglob
images=("$dest"/*-openstick-"$profile"-"$filesystem"-system.img)
manifests=("$dest"/*-openstick-"$profile".manifest)
[[ ${#images[@]} == 1 && ${#manifests[@]} == 1 ]]
simg2img "${images[0]}" "$work/system.raw"
case "$filesystem" in
    ext4) sudo mount -o loop,nodev,nosuid "$work/system.raw" "$root" ;;
    squashfs)
        sudo unsquashfs -no-progress -d "$root" "$work/system.raw"
        for tool in /sbin/firstboot /sbin/factoryreset /sbin/mount_root /usr/sbin/mkfs.f2fs; do
            test -x "$root$tool"
        done
        test ! -e "$root/etc/uci-defaults/00_rootfs_resizer"
        if grep -q '^rootfs-resizer ' "${manifests[0]}"; then exit 1; fi
        cmp "$root/lib/upgrade/platform.sh" target/linux/msm89xx/ufi/platform-fastboot-only.sh
        cmp "$root/usr/share/ufi/layout-v1" target/linux/msm89xx/ufi/layout-v1
        ;;
    *) echo "Unsupported filesystem: $filesystem" >&2; exit 1 ;;
esac
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
guest() { sudo chroot "$root" /tmp/qemu-aarch64-static "$@"; }
guest_apk() { guest "${apk#"$root"}" "$@"; }

# Derive the ABI-suffixed package names from this image so the gate also
# catches missing or multiple ABI generations when updating the pinned feeds.
mapfile -t runtime_libs < <(awk '$1 ~ /^libucode[0-9]+$/ {print $1}' "${manifests[0]}")
[[ ${#runtime_libs[@]} == 1 ]]
runtime=(ucode "${runtime_libs[0]}" ucode-mod-lua luci-base luci-lua-runtime luci-compat)
check_luci() {
    local pkg version
    [[ $(awk '/^P:libucode[0-9]+$/ {print substr($0,3)}' "$db") == "${runtime_libs[0]}" ]]
    for pkg in "${runtime[@]}" openssl-util uhttpd; do
        version=$(manifest_version "$pkg")
        check_installed "$pkg" "$version" ""
    done
    [[ $(guest /usr/bin/ucode -e 'print(type(require("lua")), "\n")') == object ]]
    echo "$board: image package versions match and the Lua bridge loads"
}

# Ensure neither the PCB profile nor a new transitive dependency brings the
# deployment-managed applications back into the factory image.
for pkg in tailscale luci-app-tailscale-community luci-app-openclash mihomo; do
    if awk -v p="$pkg" '$1 == p {found=1} END {exit !found}' "${manifests[0]}" ||
       grep -Fxq "P:$pkg" "$db"; then
        echo "$board: factory image contains deployment-managed package $pkg" >&2
        exit 1
    fi
done
core=$(sudo find "$root" -xdev \( -type f -o -type l \) \( -name clash_meta -o -name mihomo \) -print -quit)
[[ -z "$core" ]] || { echo "$board: factory image contains ${core#"$root"}" >&2; exit 1; }

check_luci
[[ -s "$root/lib/libustream-ssl.so" && -x "$root/usr/bin/openssl" ]]
for file in /etc/uhttpd.key /etc/uhttpd.crt; do
    [[ ! -e "$root$file" && ! -L "$root$file" ]]
done
# Apply the board default to the disposable root via its own UCI binary.
uci() { guest /sbin/uci "$@"; }
( . "$root/etc/uci-defaults/99-ufi-https" )
listeners=$(uci get uhttpd.main.listen_https)
for addr in '0.0.0.0:443' '[::]:443'; do
    [[ " $listeners " == *" $addr "* ]]
done
cat "$root/etc/apk/repositories.d/distfeeds.list"
guest_apk --version
guest_apk update
for pkg in tree nano; do guest_apk add --simulate "$pkg"; done

# PSG OpenClash, Tailscale, LuCI and operations dependencies. Pin the installed kernel ABI.
deps=(bash dnsmasq-full curl ca-bundle ip-full ruby ruby-yaml unzip luci-compat luci luci-base ss
      tailscale luci-app-tailscale-community)
transaction=(--allow-untrusted "/tmp/$apk_name" "kernel=$kernel" "${modules[@]}" "${deps[@]}")
guest_apk add --simulate "${transaction[@]}"
# Exercise actual installed libraries after dependency resolution. Device service
# setup, authentication and firewall behavior are verified on the boards.
# The runner builds the full host apk alongside the minimal target apk.
# Suppress package scripts on the runner while applying the same request.
sudo "$PWD/staging_dir/host/bin/apk" --root "$root" --arch aarch64_generic add \
    --no-scripts --no-commit-hooks --allow-untrusted "$work/$apk_name" \
    "kernel=$kernel" "${modules[@]}" "${deps[@]}"
check_luci
[[ -s "$root/usr/lib/lua/luci/controller/openclash.lua" ]]
[[ -s "$root/usr/share/rpcd/acl.d/luci-app-openclash.json" ]]
for pkg in tailscale luci-app-tailscale-community luci-app-openclash; do
    guest_apk info -e "$pkg"
done
ts_cli=$(sudo find "$root/usr" \( -type f -o -type l \) -name tailscale -print -quit)
[[ -n "$ts_cli" ]]
guest "${ts_cli#"$root"}" version
menu="$root/usr/share/luci/menu.d/luci-app-tailscale-community.json"
jq -er 'keys[] | select(endswith("/tailscale"))' "$menu"
echo "$board: PSG applications installed in the test copy and the Lua bridge still loads"
