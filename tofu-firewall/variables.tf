variable "proxmox_api_url" {
  description = "Proxmox VE API endpoint for the standalone firewall host, e.g. https://192.168.0.147:8006/"
  type        = string
  default     = "https://192.168.0.147:8006/"
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

variable "node_name" {
  description = "Proxmox node name of this standalone host, as it names itself (check the Datacenter view in its own web UI , this is a separate, non-clustered install from pve/pve2/pve3, so there's no shared naming to match)"
  type        = string
}

variable "vm_datastore_id" {
  description = "Datastore on this host used for the OPNsense VM's disks"
  type        = string
  default     = "local-lvm"
}

variable "opnsense_vm_id" {
  description = "Proxmox VM ID for the OPNsense VM (arbitrary , this host has no other VMs, so no collision risk)"
  type        = number
  default     = 100
}

variable "opnsense_iso_file_id" {
  description = "Proxmox volume ID of the OPNsense installer ISO, already uploaded to this host's ISO storage. The official download is bz2-compressed (https://opnsense.org/download/) , decompress it locally, then upload via this host's own Proxmox UI (Datacenter > Storage > local > ISO Images > Upload) or `pvesm`. Then point this at it, e.g. \"local:iso/OPNsense-25.7-dvd-amd64.iso\"."
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
  description = "Proxmox bridge on this host backed by the onboard NIC, used as the OPNsense WAN uplink. This bridge must have no IP address on the Proxmox host itself , anything addressed on it is exposed to the WAN side. PCI passthrough is not used: this host's onboard I219-V sits in IOMMU group 7 with the LPC bridge, SMBus and SPI controller (no ACS on this chipset), so it cannot be isolated without the ACS-override kernel patch."
  type        = string
  default     = "vmbr0"
}

variable "opnsense_lan_bridge" {
  description = "Proxmox bridge on this host backed by the second NIC, carrying both the OPNsense LAN interface and this host's own management IP , keeping mgmt here means the host stays reachable if the OPNsense VM is down or misconfigured"
  type        = string
  default     = "vmbr1"
}
