output "opnsense_vm_id" {
  description = "Proxmox VM ID of the OPNsense firewall VM"
  value       = proxmox_virtual_environment_vm.opnsense.vm_id
}
