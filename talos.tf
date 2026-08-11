resource "proxmox_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.iso_datastore_id
  node_name    = var.proxmox_node

  url       = var.talos_iso_url
  file_name = "talos-metal-amd64.iso"

  overwrite = false
}
