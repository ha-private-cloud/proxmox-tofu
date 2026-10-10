locals {
  ha_vms = merge(
    { for name, node in var.nodes : name => { vm_id = node.vm_id, node_name = node.node_name } },
    { for name, nfs in var.nfs_instances : name => { vm_id = nfs.vm_id, node_name = nfs.node_name } },
    { "ci-bastion" = { vm_id = var.bastion_vm_id, node_name = var.bastion_node_name } },
  )

  ha_nodes = toset([for vm in local.ha_vms : vm.node_name])
}

resource "proxmox_haresource" "vm" {
  for_each = local.ha_vms

  resource_id = "vm:${each.value.vm_id}"
  state       = "started"
  comment     = "Auto-restart ${each.key} if it crashes"
}

resource "proxmox_harule" "node_affinity" {
  for_each = local.ha_nodes

  rule    = "pin-${each.value}"
  type    = "node-affinity"
  nodes   = { (each.value) = 1 }
  strict  = true
  comment = "All VMs on ${each.value} - local storage, never relocate"

  resources = [
    for name, vm in local.ha_vms : "vm:${vm.vm_id}" if vm.node_name == each.value
  ]

  depends_on = [proxmox_haresource.vm]
}
