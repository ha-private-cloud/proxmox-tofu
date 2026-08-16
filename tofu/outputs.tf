output "vm_ids" {
  description = "Map of VM name to Proxmox VM ID"
  value       = { for k, v in proxmox_virtual_environment_vm.talos : k => v.vm_id }
}

output "nfs_vm_id" {
  description = "Map of NFS storage VM name to Proxmox VM ID"
  value       = { for k, v in proxmox_virtual_environment_vm.nfs : k => v.vm_id }
}

output "bastion_vm_id" {
  description = "Proxmox VM ID of the CI bastion."
  value       = proxmox_virtual_environment_vm.bastion.vm_id
}
