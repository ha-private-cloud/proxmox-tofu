#!/usr/bin/env bash
# One-time bootstrap for the nfs-storage VM: formats and mounts the second
# (data) disk Tofu attached at scsi1 (shows up as /dev/sdb in the guest),
# installs nfs-kernel-server, and exports it to the cluster subnet.
#
# Run this on the nfs-storage VM itself, e.g.:
#   ssh admin@<nfs-storage-ip> 'sudo bash -s' < scripts/setup-nfs-server.sh
#
# Safe to re-run: skips formatting if the data disk is already formatted
# and mounted, and exportfs/apt steps are idempotent.

set -euo pipefail

DATA_DISK="/dev/sdb"
MOUNT_POINT="/srv/nfs/data"
EXPORT_SUBNET="192.168.0.0/24" # must match the subnet the cluster nodes are on, or every existing NFS mount is cut off on the next re-run.

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (e.g. via sudo)." >&2
  exit 1
fi

if [ ! -b "$DATA_DISK" ]; then
  echo "Expected data disk $DATA_DISK not found. Check the VM's disk layout (lsblk)." >&2
  exit 1
fi

echo "==> Installing nfs-kernel-server"
apt-get update -qq
apt-get install -y -qq nfs-kernel-server >/dev/null

if ! blkid "$DATA_DISK" >/dev/null 2>&1; then
  echo "==> Formatting $DATA_DISK as ext4"
  mkfs.ext4 -q -L nfsdata "$DATA_DISK"
else
  echo "==> $DATA_DISK already has a filesystem, skipping format"
fi

mkdir -p "$MOUNT_POINT"

DATA_DISK_UUID="$(blkid -s UUID -o value "$DATA_DISK")"
FSTAB_LINE="UUID=${DATA_DISK_UUID}  ${MOUNT_POINT}  ext4  defaults  0  2"
if ! grep -qs "$DATA_DISK_UUID" /etc/fstab; then
  echo "==> Adding fstab entry"
  echo "$FSTAB_LINE" >> /etc/fstab
fi

if ! mountpoint -q "$MOUNT_POINT"; then
  echo "==> Mounting $MOUNT_POINT"
  mount "$MOUNT_POINT"
fi

chown nobody:nogroup "$MOUNT_POINT"
chmod 0770 "$MOUNT_POINT"

EXPORT_LINE="${MOUNT_POINT} ${EXPORT_SUBNET}(rw,sync,no_subtree_check,no_root_squash)"
if ! grep -qs "^${MOUNT_POINT} " /etc/exports; then
  echo "==> Adding NFS export for ${EXPORT_SUBNET}"
  echo "$EXPORT_LINE" >> /etc/exports
fi

exportfs -ra
systemctl enable --now nfs-kernel-server
systemctl restart nfs-kernel-server

echo "==> Done. Exported ${MOUNT_POINT} to ${EXPORT_SUBNET}"
exportfs -v
