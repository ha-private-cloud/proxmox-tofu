variable "proxmox_api_url" {
  description = "Proxmox VE API endpoint for the standalone firewall host, e.g. https://192.168.0.147:8006/"
  type        = string
  default     = "https://192.168.0.147:8006/"
}

variable "proxmox_insecure" {
  description = "Skip TLS certificate verification"
  type        = bool
  default     = true
}

variable "proxmox_username" {
  description = "Proxmox username including realm, e.g. root@pam"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Proxmox password for proxmox_username"
  type        = string
  sensitive   = true
}

variable "node_name" {
  description = "Proxmox node name of the standalone firewall host"
  type        = string
}

variable "vm_datastore_id" {
  description = "Datastore on this host used for the OPNsense VM's disks"
  type        = string
  default     = "local-lvm"
}

variable "opnsense_vm_id" {
  description = "Proxmox VM ID for the OPNsense VM"
  type        = number
  default     = 100
}

variable "opnsense_iso_file_id" {
  description = "Proxmox volume ID of the OPNsense installer ISO, e.g. local:iso/OPNsense-25.7-dvd-amd64.iso"
  type        = string
}

variable "opnsense_cpu_cores" {
  description = "vCPU cores for the OPNsense VM"
  type        = number
  default     = 2
}

variable "opnsense_memory" {
  description = "Memory for the OPNsense VM, in MB"
  type        = number
  default     = 4096
}

variable "opnsense_disk_size" {
  description = "Disk size for the OPNsense VM, in GB"
  type        = number
  default     = 20
}

variable "opnsense_wan_bridge" {
  description = "Proxmox bridge for the OPNsense WAN uplink"
  type        = string
  default     = "vmbr0"
}

variable "opnsense_lan_bridge" {
  description = "Proxmox bridge for the OPNsense LAN interface"
  type        = string
  default     = "vmbr1"
}
