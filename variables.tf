variable "proxmox_api_url" {
  description = "Proxmox VE API endpoint, e.g. https://192.168.0.242:8006/"
  type        = string
  default     = "https://192.168.0.242:8006/"
}

variable "proxmox_insecure" {
  description = "Skip TLS certificate verification (needed for self-signed Proxmox certs)"
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

variable "proxmox_node" {
  description = "Name of the Proxmox node to deploy VMs on (as shown in the Proxmox UI)"
  type        = string
  default     = "pve"
}

variable "iso_datastore_id" {
  description = "Datastore used to store the downloaded Talos ISO"
  type        = string
  default     = "local"
}

variable "vm_datastore_id" {
  description = "Datastore used for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Proxmox network bridge to attach VM NICs to"
  type        = string
  default     = "vmbr0"
}

variable "talos_iso_url" {
  description = "URL of the Talos Linux metal ISO to download onto the Proxmox node"
  type        = string
  default     = "https://github.com/siderolabs/talos/releases/latest/download/metal-amd64.iso"
}

variable "vm_cpu_cores" {
  description = "vCPU cores per VM"
  type        = number
  default     = 4
}

variable "vm_memory" {
  description = "Memory per VM in MB"
  type        = number
  default     = 4096
}

variable "vm_disk_size" {
  description = "Disk size per VM in GB"
  type        = number
  default     = 32
}

variable "nodes" {
  description = "Talos cluster nodes to create"
  type = map(object({
    vm_id = number
  }))
  default = {
    "talos-cp-1"     = { vm_id = 901 }
    "talos-worker-1" = { vm_id = 902 }
    "talos-worker-2" = { vm_id = 903 }
  }
}
