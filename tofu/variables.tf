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

variable "cluster_vlan_id" {
  description = "802.1Q VLAN ID all Talos + NFS storage VM traffic is tagged with, isolating it from the flat LAN. The Proxmox hosts' own management stays untagged/native on the same physical NIC , only VM traffic is tagged. The switch ports facing each Proxmox host must be configured as trunk ports allowing this VLAN (see ../cluster-network)."
  type        = number
  default     = 10
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

variable "nfs_vm_cpu_cores" {
  description = "vCPU cores for the NFS storage VM"
  type        = number
  default     = 2
}

variable "nfs_vm_memory" {
  description = "Memory for the NFS storage VM, in MB"
  type        = number
  default     = 2048
}

variable "nfs_os_disk_size" {
  description = "OS disk size for the NFS storage VM, in GB (imported from the Debian cloud image, then grown to this size)"
  type        = number
  default     = 16
}

variable "nfs_data_disk_size" {
  description = "Size of the dedicated data disk exported over NFS, in GB"
  type        = number
  default     = 200
}

variable "nfs_debian_cloud_image_url" {
  description = "URL of the Debian generic cloud qcow2 image used for the NFS storage VM"
  type        = string
  default     = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
}

variable "nfs_admin_username" {
  description = "Cloud-init admin username created on the NFS storage VM"
  type        = string
  default     = "admin"
}

variable "nfs_ssh_public_key_path" {
  description = "Path to an SSH public key installed for nfs_admin_username via cloud-init"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "nodes" {
  description = "Talos cluster nodes to create, and which Proxmox host each lands on"
  type = map(object({
    vm_id     = number
    node_name = string
  }))
  default = {
    "talos-cp-1"     = { vm_id = 901, node_name = "pve" }
    "talos-worker-1" = { vm_id = 902, node_name = "pve" }
    "talos-worker-2" = { vm_id = 903, node_name = "pve" }
    "talos-cp-2"     = { vm_id = 911, node_name = "pve2" }
    "talos-worker-3" = { vm_id = 912, node_name = "pve2" }
    "talos-worker-4" = { vm_id = 913, node_name = "pve2" }
    "talos-cp-3"     = { vm_id = 921, node_name = "pve3" }
    "talos-worker-5" = { vm_id = 922, node_name = "pve3" }
    "talos-worker-6" = { vm_id = 923, node_name = "pve3" }
  }
}

variable "nfs_instances" {
  description = "NFS storage VMs to create, and which Proxmox host each lands on"
  type = map(object({
    vm_id     = number
    node_name = string
  }))
  default = {
    "nfs-storage-pve2" = { vm_id = 914, node_name = "pve2" }
    "nfs-storage-pve3" = { vm_id = 924, node_name = "pve3" }
  }
}
