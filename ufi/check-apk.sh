#!/usr/bin/env bash
# Resolve representative official packages against a disposable copy of the installed DB.
set -eu
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
src=$1
apk=$2
for path in etc/apk lib/apk usr/lib/apk; do
    if [ -d "$src/$path" ]; then
        mkdir -p "$root/${path%/*}"
        cp -a "$src/$path" "$root/$path"
    fi
done
mkdir -p "$root/tmp"
cat "$root/etc/apk/repositories.d/distfeeds.list"
# --no-scripts and --simulate avoid running target binaries or changing the image.
args=(--root "$root" --arch aarch64_generic --no-scripts --no-cache)
"$apk" "${args[@]}" update || exit $?
for package in tree nano; do
    echo "=== simulate $package ==="
    "$apk" "${args[@]}" add --simulate "$package" || exit $?
done
