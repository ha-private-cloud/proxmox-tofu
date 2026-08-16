provider "proxmox" {
  endpoint = var.proxmox_api_url
  insecure = var.proxmox_insecure

  username = var.proxmox_username
  password = var.proxmox_password
}
