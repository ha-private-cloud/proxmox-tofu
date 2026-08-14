#!/usr/bin/env bash
# Finds the new VMs' DHCP-assigned IPs by scanning the LAN, since Proxmox
# can't report them itself (qemu-guest-agent is disabled on both the Talos
# and NFS VMs , see vms.tf / nfs-storage.tf). Talos VMs are identified by
# their maintenance-mode API port (50000); NFS VMs are identified by SSHing
# in (cloud-init trusts the same key as nfs_ssh_public_key_path) and reading
# their hostname, which cloud-init sets to match the Tofu resource name.
set -euo pipefail

SUBNET_PREFIX="${1:-192.168.0}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_USER="${SSH_USER:-admin}"
MAX_PARALLEL=40

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

echo "Scanning ${SUBNET_PREFIX}.0/24 for live hosts..." >&2
count=0
for i in $(seq 1 254); do
  ip="${SUBNET_PREFIX}.${i}"
  ( ping -c1 -W1 "$ip" >/dev/null 2>&1 && touch "$tmp_dir/$ip" ) &
  count=$((count + 1))
  if (( count % MAX_PARALLEL == 0 )); then
    wait
  fi
done
wait

live_hosts=$(ls "$tmp_dir" | sort -t. -k4 -n)
live_count=$(printf '%s\n' "$live_hosts" | grep -c . || true)
echo "Found $live_count live host(s). Probing port 50000 (Talos) and 22 (SSH)..." >&2

talos_ips=()
nfs_results=()

for ip in $live_hosts; do
  if timeout 1 bash -c "cat < /dev/null > /dev/tcp/$ip/50000" 2>/dev/null; then
    talos_ips+=("$ip")
  elif timeout 1 bash -c "cat < /dev/null > /dev/tcp/$ip/22" 2>/dev/null; then
    hostname=$(ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=2 \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "$SSH_USER@$ip" hostname 2>/dev/null || true)
    if [[ "$hostname" == nfs-storage-* ]]; then
      nfs_results+=("$hostname -> $ip")
    fi
  fi
done

echo
echo "=== Talos nodes (port 50000 open, maintenance mode) , ${#talos_ips[@]} found, 9 expected ==="
if [[ ${#talos_ips[@]} -eq 0 ]]; then
  echo "  none found"
else
  printf '  %s\n' "${talos_ips[@]}"
fi
echo "  Note: Talos doesn't expose per-node identity until machine config is"
echo "  applied, so these can't be mapped back to specific talos-cp-N /"
echo "  talos-worker-N names by IP alone , any 3 of them can become control"
echo "  planes when you run talosctl apply-config."

echo
echo "=== NFS storage VMs (identified via SSH hostname) ==="
if [[ ${#nfs_results[@]} -eq 0 ]]; then
  echo "  none found"
else
  printf '  %s\n' "${nfs_results[@]}"
fi
