# proxmox-tofu

Tofu infrastructure-as-code for deploying Kubernetes nodes on the Proxmox VE hosts

Plan:
- Provisions 3 VMs per host across the 3-node Proxmox cluster (`pve`, `pve2`, `pve3`): 1 control plane, 2 workers each , 9 Talos VMs total
- Use talos iso for VMs

## Prerequisites

- [OpenTofu](https://opentofu.org/) installed
- [`talosctl`](https://www.talos.dev/latest/talos-guides/install/talosctl/) installed locally, for the post-provisioning steps

## Usage

Create your terraform.tfvars, here's an example:
```
proxmox_api_url  = ""
proxmox_username = ""
proxmox_password = ""
iso_datastore_id = ""
vm_datastore_id  = ""
network_bridge = ""
```

Run tofu:

```sh
cd tofu
tofu init
tofu plan
tofu apply
```

This downloads the latest Talos ISO to each of the 3 Proxmox hosts and creates 9 Talos VMs (3 per host), plus 2 NFS storage VMs , see below. Everything past this point (`_out/`, `scripts/`, `talosctl`) still runs from the repo root, not `tofu/` , only `tofu` commands themselves moved.

## NFS storage VMs

The Talos VMs' disks are fully allocated to Talos's own partitions (no free space for a Kubernetes StorageClass), so cluster storage is provided by two separate, plain Debian VMs running NFS servers instead , `nfs-storage-pve2` and `nfs-storage-pve3`, one per host (`pve2`/`pve3` have more disk than `pve`, which is kept dedicated to Talos nodes). These are two independent 200GB exports, not a replicated pair. Tofu provisions the VMs and their disks only; the NFS server software itself is set up by a script you run once per VM, the same manual-bootstrap pattern used for `talosctl` below.

1. Find each VM's DHCP IP (this is on the Proxmox console).
2. Run the setup script over SSH against **each** NFS VM (cloud-init creates the `admin` user with your `~/.ssh/id_ed25519` key):

   ```sh
   ssh admin@<nfs-storage-pve2-ip> 'sudo bash -s' < scripts/setup-nfs-server.sh
   ssh admin@<nfs-storage-pve3-ip> 'sudo bash -s' < scripts/setup-nfs-server.sh
   ```

   This installs `nfs-kernel-server`, formats and mounts the 200GB data disk at `/srv/nfs/data`, and exports it to `192.168.0.0/24` (edit `EXPORT_SUBNET` in the script if your LAN differs). Safe to re-run.
3. Both exports are wired into `cluster-config`'s `csi-driver-nfs` install as separate StorageClasses (`nfs-csi`, the default, on `pve2`; `nfs-csi-pve3` on `pve3`) , see that repo's `csi-driver-nfs.tf`.

## CI bastion

A plain openSUSE Leap VM (`ci-bastion`, on `pve`) that runs GitHub Actions self-hosted runners for the app repos (`clusterkeep-ui` to start). It's the one place, besides your own workstation, allowed to hold the files that can't live in git , the kubeconfig, each repo's `tofu/terraform.tfvars`, and `~/.config/cluster-cli/config.toml`.

1. `tofu apply` (above) creates it , find its DHCP IP via `scripts/find-vm-ips.sh` or the Proxmox console.
2. Bootstrap it (installs git, uv, tofu, helm, kubectl, the GitHub Actions runner binary; safe to re-run):
   ```sh
   ssh admin@<bastion-ip> 'sudo bash -s' < scripts/setup-bastion.sh
   ```
3. Copy over the kubeconfig, each repo's `terraform.tfvars`, and a `~/.config/cluster-cli/config.toml` built from `cluster-ci`'s `runner_api_token` output , see the script's own printed output for exact paths.
4. Clone the repos it needs (`cluster-cli`, `cluster-ci`, `clusterkeep-ui`, `cluster-config`, `proxmox-tofu`, `cluster-auth`) into `~/project/`. Use a dedicated deploy key per repo rather than your own , GitHub deploy keys are repo-scoped anyway.
5. Register the runner against each repo needing it (Settings -> Actions -> Runners -> New self-hosted runner gives the exact token/command):
   ```sh
   cd ~/actions-runner && ./config.sh --url <repo-url> --token <token>
   sudo ./svc.sh install && sudo ./svc.sh start
   ```
6. Pushes to `clusterkeep-ui`'s `dev`/`preview`/`main` branches then trigger `.github/workflows/build.yml` there, which builds via `cluster-ci` and deploys via that repo's own Tofu.

To rebuild on a different image: back up `~/.ssh` and `~/project` first, then `tofu apply -replace=proxmox_virtual_environment_vm.bastion` (just changing `disk.import_from` doesn't re-import an existing disk).

## Adding new Talos nodes to an existing cluster

Tofu only creates the VMs; turning a freshly-created VM (booted into Talos's insecure maintenance mode) into an actual cluster member is a manual `talosctl` step, same as the original bootstrap. Find the new VM's IP (`scripts/find-vm-ips.sh` can help , see its header comment for why Proxmox can't just report it), then:

```sh
talosctl apply-config --insecure -n <new-node-ip> -f _out/controlplane.yaml   # for a new control plane
talosctl apply-config --insecure -n <new-node-ip> -f _out/worker.yaml        # for a new worker
```

This reuses the **existing** `_out/controlplane.yaml`/`worker.yaml` , same `cluster.id`/`cluster.secret` as the live cluster , so the node discovers and joins automatically via the `discovery.enabled` service registry. **Do not run `talosctl bootstrap` again** , that's a one-time-ever operation for the very first control-plane node; running it a second time against an existing cluster risks a split-brain etcd. Verify with:

```sh
talosctl etcd members --nodes <any-cp-ip> --endpoints <any-cp-ip> --talosconfig _out/talosconfig
KUBECONFIG=_out/kubeconfig kubectl get nodes
```

New nodes typically show `NotReady` for the first ~30-60s (CNI/kubelet sync) and new control planes join etcd as a `LEARNER` before being promoted to a full voting member shortly after , both resolve on their own.

## OIDC-authenticated cluster access

`talos-oidc-patch.yaml` makes the apiserver trust Authentik (see `cluster-auth`) as an OIDC issuer, so Headlamp logins authenticate as the actual user rather than failing , `cluster-rbac` then grants each user a ClusterRole via their OIDC identity. Requires `cluster-auth` already applied (the patch embeds its Authentik ingress CA cert).

This changes the live control-plane's apiserver config, so it's not run as part of `tofu apply` , apply it yourself once per control-plane node, and again any time the CA cert block in the patch file is regenerated. With 3 control planes, apply it **one node at a time**, waiting for each to come back before moving to the next:

```sh
for ip in 10.10.10.11 10.10.10.21 10.10.10.31; do  # talos-cp-1/2/3 , see ../cluster-network for the addressing scheme
  talosctl patch mc --patch-file talos-oidc-patch.yaml \
    --nodes "$ip" --endpoints "$ip" \
    --talosconfig _out/talosconfig
done
```

Unlike most Talos config patches, this one **reboots the control-plane node**. With 3 control planes, patching them one at a time keeps the cluster available throughout, the other two CPs keep serving while one reboots. Verify each one with:

```sh
KUBECONFIG=_out/kubeconfig kubectl get pods -n kube-system -l component=kube-apiserver
```

If it doesn't come back `Running`, the most likely causes are a DNS/TLS mismatch reaching `auth.talos.lab` from the control-plane node itself (check `extraHostEntries` resolves and the CA cert is current) , the existing client-certificate kubeconfig in `_out/` still works regardless, since OIDC is an additional auth method, not a replacement for it.
