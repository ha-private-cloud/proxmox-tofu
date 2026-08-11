# proxmox-tofu

Tofu infrastructure-as-code for deploying Kubernetes nodes on the Proxmox VE hosts

Plan:
- Provisions 3 VMs per host. 1 control plane, 2 workers
- Use talos iso for VMs
- 

## Prerequisites

- [OpenTofu](https://opentofu.org/) installed
- [`talosctl`](https://www.talos.dev/latest/talos-guides/install/talosctl/)
  installed locally, for the post-provisioning steps

## Usage

Create your terraform.tfvars, here's an example:
```
proxmox_api_url  = ""
proxmox_username = ""
proxmox_password = ""
proxmox_node = ""
iso_datastore_id = ""
vm_datastore_id  = ""
network_bridge = ""
```

Run tofu:

```sh
tofu init
tofu plan
tofu apply
```

This downloads the latest Talos ISO to the node and creates 3 VMs


