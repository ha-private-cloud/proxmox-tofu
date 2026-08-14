moved {
  from = proxmox_download_file.talos_iso
  to   = proxmox_download_file.talos_iso["pve"]
}

resource "proxmox_download_file" "talos_iso" {
  for_each = toset([for n in var.nodes : n.node_name])

  content_type = "iso"
  datastore_id = var.iso_datastore_id
  node_name    = each.key

  url       = var.talos_iso_url
  file_name = "talos-metal-amd64.iso"

  overwrite = false
}
