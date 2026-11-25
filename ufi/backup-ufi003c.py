#!/usr/bin/env python3
"""Save UFI003C configuration and eMMC boot areas to a new host directory over SSH."""
import argparse
import hashlib
import subprocess
import tarfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host", help="SSH destination, e.g. root@192.168.1.1")
    parser.add_argument("directory", type=Path, help="new private backup directory")
    args = parser.parse_args()
    ssh = ["ssh", "-T", "--", args.host]
    layout = Path(__file__).resolve().parents[1] / "target/linux/msm89xx/ufi/layout-ufi003c-v1"
    probe = """set -e
test "$(cat /sys/class/block/mmcblk0/size)" = 7634944
for n in $(seq 1 14); do
    d=/sys/class/block/mmcblk0p$n
    printf '%s %s %s %s\n' "$n" "$(sed -n 's/^PARTNAME=//p' "$d/uevent")" "$(cat "$d/start")" "$(cat "$d/size")"
done"""
    observed = subprocess.check_output(ssh + [probe]).decode().splitlines()
    if observed != layout.read_text().splitlines():
        raise SystemExit("Unexpected partition layout")
    out = args.directory
    out.mkdir(mode=0o700, parents=True, exist_ok=False)
    (out / "layout.txt").write_text("\n".join(observed) + "\n")
    def save(name, command):
        partial = out / (name + ".partial")
        with partial.open("xb") as stream:
            subprocess.run(ssh + [command], stdout=stream, check=True)
        return partial

    for area in ("mmcblk0boot0", "mmcblk0boot1"):
        dev = "/dev/" + area
        partial = save(area + ".img", "dd if=" + dev + " bs=1M")
        device_hash = subprocess.check_output(ssh + ["sha256sum " + dev]).decode().split()[0]
        if partial.stat().st_size != 4194304 or hashlib.sha256(partial.read_bytes()).hexdigest() != device_hash:
            raise SystemExit("Boot area verification failed: " + area)
        partial.rename(out / (area + ".img"))

    archive = save("config.tar.gz", 'set -e; d=$(mktemp -d); trap \'rm -rf "$d"\' EXIT; sysupgrade -b "$d/config.tar.gz" >&2; cat "$d/config.tar.gz"')
    with tarfile.open(archive, "r:gz") as tar:
        if not tar.getnames():
            raise SystemExit("Empty configuration archive")
    archive.rename(out / "config.tar.gz")
    sums = [hashlib.sha256(p.read_bytes()).hexdigest() + "  " + p.name for p in sorted(out.iterdir())]
    (out / "SHA256SUMS").write_text("\n".join(sums) + "\n")
    print("Saved configuration and both boot areas in", out)


if __name__ == "__main__":
    main()
