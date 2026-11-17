# proxmox-tofu

This repository contains the base infrastructure for ClusterKeep, the virtual machines on the three Proxmox hosts, built with OpenTofu. Everything else in ClusterKeep runs on top of what this creates.

## What it creates

| VMs | Where | What they're for |
|---|---|---|
| 9 Talos VMs: 3 control planes and 6 workers | One control plane and two workers on each of `pve`, `pve2` and `pve3` | The Kubernetes cluster. Each has 4 cores, 4 GB of memory and a 32 GB disk |
| `nfs-storage-pve2` and `nfs-storage-pve3` | One each on `pve2` and `pve3` | A highly available Debian NFS pair. Each has a 235 GB data disk, mirrored between them with DRBD, and together they hold every persistent volume |
| `ci-bastion` | `pve` | openSUSE VM that runs the GitHub Actions runners, the internal DNS and the files that can't live in Git |

OpenTofu tracks the Talos VMs by their VM ID, so renaming one in `nodes` only changes its name.

Proxmox's HA manager restarts a VM if it crashes. Each VM is pinned to its own host because its disk is local, so it never moves to another one. Spreading a control plane to each host means the cluster keeps running with any single host off.

`tofu-firewall/` is a separate OpenTofu config with its own state for the OPNsense firewall VM on a standalone Proxmox host. It's kept apart so the firewall can never affect the cluster's quorum.

## Using it

All the main OpenTofu files are in `tofu/`. The tfvars on the CI bastion hold the Proxmox address, login and datastores.

Pushing a `vX.Y.Z` tag plans the change through the shared `pipelines` workflow, and applying it is always a manual run of that workflow. Some changes replace VMs, so read the plan carefully. The firewall uses its own `fw-vX.Y.Z` tags so a normal release never touches it.

Talos itself is set up with `talosctl` once the VMs exist. The generated configs, `talosconfig` and kubeconfig live in `_out/`, which is kept out of Git.

## Talos patches

These change the live nodes, so they're applied with `talosctl` rather than OpenTofu.

| Patch | What it does | Applied |
|---|---|---|
| `talos-auth-api-patch.yaml` with `talos-oidc-removal.yaml` | Makes the Kubernetes API trust auth.clusterkeep.com for Headlamp logins and removes the old Authentik settings | On every control plane |
| `talos-auth-api-hosts-patch.yaml` | Points auth.clusterkeep.com at the local ingress | Not yet. It needs a local ingress for auth-api with a trusted certificate first |

The registry and static address patches are in `cluster-network`.

`talos-auth-api-patch.yaml` writes a file onto the node, so Talos reboots it. Apply it to one control plane at a time and wait for that node, its API server and etcd to be healthy before moving on. The talosconfig has no endpoints set, so pass the node each time:

```sh
talosctl --talosconfig _out/talosconfig -n <control-plane-ip> -e <control-plane-ip> \
  patch machineconfig --patch @talos-oidc-removal.yaml --patch @talos-auth-api-patch.yaml
```

## NFS storage VMs

The two NFS VMs are one active/passive service. DRBD mirrors the data disk between them synchronously, so a write is on both hosts before it's acknowledged. Pacemaker runs the mount, the NFS server, the export and the shared service address on whichever VM holds the DRBD primary, and moves all of them to the other VM if that one fails. Every StorageClass points at the shared address, so the cluster never needs to know which VM is serving.

A quorum device on the bastion breaks ties between the two. Each VM has a Proxmox i6300ESB watchdog set to reset it, and SBD uses that watchdog to reset a VM that loses quorum, so the other one can take over without both writing to the disk.

Prepare each VM over SSH first. The script installs the packages, leaves the NFS server to Pacemaker and makes sure the i6300ESB is always `/dev/watchdog0`.

```sh
ssh admin@<nfs-vm-ip> 'sudo bash -s' < scripts/setup-nfs-server.sh
```

Building the pair is a one-off after that.

1. Form the cluster with `pcs`, add the bastion as a `net` quorum device, and set the device's `timeout` to 5000 and `sync_timeout` to 8000. SBD won't trust the quorum device if its sync timeout is longer than the watchdog timeout, and Pacemaker never starts.
2. Turn on SBD with `pcs stonith sbd enable watchdog=/dev/watchdog0 SBD_WATCHDOG_TIMEOUT=10`, restart the cluster, then set `stonith-watchdog-timeout=20` and `stonith-enabled=true`.
3. Write the DRBD resource `nfs` to `/etc/drbd.d/` on both VMs with protocol C, a shared secret and the `crm-fence-peer.sh` handlers. Create its metadata with `drbdadm -- --force create-md nfs`, since `create-md` reads its confirmation from the terminal. On a disk that already holds data, the metadata goes in the space past the filesystem, so grow the disk first.
4. On the VM with the data, make DRBD primary and lay the filesystem out as `data/` for the volumes and `nfsinfo/` for the NFS server's state, then mount it at `/srv/nfs`.
5. Create the Pacemaker resources: a promotable DRBD clone and a group of `Filesystem` on `/srv/nfs`, `nfsserver` with `nfs_shared_infodir=/srv/nfs/nfsinfo` and a 90 second start timeout, `exportfs` for `/srv/nfs/data`, then `IPaddr2` for the shared address. Colocate the group with the promoted clone and start it after promotion.

If an fstab entry for the data disk is removed, run `systemctl daemon-reload` before starting the NFS server. Otherwise systemd keeps waiting for the old mount and the start times out.

Check the pair with `sudo crm_mon -1r` and `sudo drbdadm status nfs`. `sudo pcs node standby <vm>` moves the service off a VM for maintenance, and `sudo pcs node unstandby <vm>` brings it back. Resources stay where they are afterwards rather than moving straight back.

## CI bastion

1. Find the bastion's address with `scripts/find-vm-ips.sh` or the Proxmox console, then set it up:

   ```sh
   ssh admin@<bastion-ip> 'sudo bash -s' < scripts/setup-bastion.sh
   ```

2. Copy over the kubeconfig, every repo's tfvars and cluster-cli's `config.toml`.
3. Give each repo its own read-only deploy key and an SSH alias, then clone it into `~/project/` through that alias.
4. Register the three runners against the `ha-private-cloud` organisation rather than a single repo, so any repo's jobs can use them.

## Adding a Talos node

OpenTofu only creates the VM. Once it has booted into Talos maintenance mode, give it the existing config:

```sh
talosctl apply-config --insecure -n <new-node-ip> -f _out/controlplane.yaml
talosctl apply-config --insecure -n <new-node-ip> -f _out/worker.yaml
```

Use the first for a control plane and the second for a worker. The node joins by itself. Never run `talosctl bootstrap` again on a cluster that already exists.

## Technologies

OpenTofu with the bpg Proxmox provider, Talos Linux, Debian with NFS, openSUSE for the bastion and OPNsense for the firewall.
