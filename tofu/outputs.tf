output "vm_ids" {
  description = "Map of VM name to Proxmox VM ID"
  value       = { for k, v in proxmox_virtual_environment_vm.talos : k => v.vm_id }
}

output "nfs_vm_id" {
  description = "Map of NFS storage VM name to Proxmox VM ID"
  value       = { for k, v in proxmox_virtual_environment_vm.nfs : k => v.vm_id }
}

output "nfs_admin_username" {
  description = "Cloud-init admin username on the NFS storage VM"
  value       = var.nfs_admin_username
}

output "nfs_console_password" {
  description = "Map of NFS storage VM name to its console-login password (SSH normally uses the key instead; this is just for finding its DHCP IP via the Proxmox console)."
  value       = { for k, v in random_password.nfs_console : k => v.result }
  sensitive   = true
}

output "note" {
  value = "VMs get DHCP addresses; find them via your router's DHCP leases or the Proxmox console, then proceed with talosctl (see README.md) for the Talos nodes, or scripts/setup-nfs-server.sh for the NFS storage VM."
}
