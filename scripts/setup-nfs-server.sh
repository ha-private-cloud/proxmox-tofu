#!/usr/bin/env bash
# Bootstrap the nfs-storage VM: format/mount the data disk at scsi1 (/dev/sdb),
# install nfs-kernel-server, export it to the cluster subnet.
#
# Run on the VM itself:
#   ssh admin@<nfs-storage-ip> 'sudo bash -s' < scripts/setup-nfs-server.sh
#
# Safe to re-run.

set -euo pipefail

DATA_DISK="/dev/sdb"
MOUNT_POINT="/srv/nfs/data"
EXPORT_SUBNET="192.168.0.0/24"

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
