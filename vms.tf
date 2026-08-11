resource "proxmox_virtual_environment_vm" "talos" {
  for_each = var.nodes

  name      = each.key
  node_name = var.proxmox_node
  vm_id     = each.value.vm_id

  bios    = "ovmf"
  machine = "q35"

  cpu {
    cores = var.vm_cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.vm_memory
  }

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    size         = var.vm_disk_size
    file_format  = "raw"
  }

  efi_disk {
    datastore_id = var.vm_datastore_id
    type         = "4m"
  }

  cdrom {
    file_id   = proxmox_download_file.talos_iso.id
    interface = "ide3"
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  # Boots from disk once Talos is installed; falls back to the ISO
  # (maintenance mode) whenever the disk has no bootable install yet.
  boot_order = ["scsi0", "ide3"]

  agent {
    enabled = false
  }

  operating_system {
    type = "l26"
  }
}
