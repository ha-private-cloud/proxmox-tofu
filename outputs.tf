output "vm_ids" {
  description = "Map of VM name to Proxmox VM ID"
  value       = { for k, v in proxmox_virtual_environment_vm.talos : k => v.vm_id }
}

output "note" {
  value = "VMs get DHCP addresses; find them via your router's DHCP leases or the Proxmox console, then proceed with talosctl (see README.md)."
}
