# Proxmox's on_boot (default true on every VM here) only restarts VMs when
# the Proxmox host itself reboots , it does nothing if a VM crashes while
# the host stays up (what happened to the bastion). HA resources are what
# actually monitor and restart a crashed VM , applied here to every VM in
# the project: the 9 Talos nodes, both NFS storage VMs, and the bastion.
#
# One HA group per Proxmox host, restricted = true, since every VM's disk
# is on that host's local (non-shared) storage , without restricted,
# Proxmox's HA manager could try to start a VM on a different node, where
# its disk doesn't exist, and fail.
locals {
  ha_vms = merge(
    { for name, node in var.nodes : name => { vm_id = node.vm_id, node_name = node.node_name } },
    { for name, nfs in var.nfs_instances : name => { vm_id = nfs.vm_id, node_name = nfs.node_name } },
    { "ci-bastion" = { vm_id = var.bastion_vm_id, node_name = var.bastion_node_name } },
  )

  ha_nodes = toset([for vm in local.ha_vms : vm.node_name])
}

resource "proxmox_hagroup" "node" {
  for_each = local.ha_nodes

  group      = each.value
  comment    = "All VMs on ${each.value} , local storage, never relocate"
  nodes      = { (each.value) = 1 }
  restricted = true
}

resource "proxmox_haresource" "vm" {
  for_each = local.ha_vms

  resource_id = "vm:${each.value.vm_id}"
  group       = proxmox_hagroup.node[each.value.node_name].group
  state       = "started"
  comment     = "Auto-restart ${each.key} if it crashes"
}
