#!/usr/bin/env bash
set -euo pipefail

DATA_DISK="/dev/sdb"
MOUNT_POINT="/srv/nfs"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (e.g. via sudo)." >&2
  exit 1
fi

if [ ! -b "$DATA_DISK" ]; then
  echo "Expected data disk $DATA_DISK not found. Check the VM's disk layout (lsblk)." >&2
  exit 1
fi

echo "==> Installing NFS, DRBD and Pacemaker packages"
apt-get update -qq
apt-get install -y -qq nfs-kernel-server drbd-utils pacemaker corosync corosync-qdevice pcs sbd resource-agents >/dev/null

echo "==> Leaving the NFS server to Pacemaker"
systemctl disable --now nfs-server >/dev/null 2>&1 || true

if grep -qsE "^[^#].*[[:space:]]/srv/nfs(/data)?[[:space:]]" /etc/fstab; then
  echo "==> Commenting out the old data disk fstab entry"
  cp -a /etc/fstab "/root/fstab.$(date +%s)"
  sed -i -E "s|^([^#].*[[:space:]]/srv/nfs(/data)?[[:space:]].*)$|#\1|" /etc/fstab
  systemctl daemon-reload
fi

if grep -qsE "^/srv/nfs" /etc/exports; then
  echo "==> Commenting out static exports"
  cp -a /etc/exports "/root/exports.$(date +%s)"
  sed -i -E "s|^(/srv/nfs.*)$|#\1|" /etc/exports
fi

echo "==> Keeping the i6300ESB as /dev/watchdog0 for SBD"
echo "blacklist iTCO_wdt" > /etc/modprobe.d/blacklist-itco-wdt.conf

mkdir -p "$MOUNT_POINT"

echo "==> Done. Finish the pair with the one-off cluster steps in the README."
