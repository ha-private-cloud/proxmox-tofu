resource "proxmox_virtual_environment_vm" "opnsense" {
  name      = "opnsense"
  node_name = var.node_name
  vm_id     = var.opnsense_vm_id

  bios    = "ovmf"
  machine = "q35"

  cpu {
    cores = var.opnsense_cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.opnsense_memory
  }

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    size         = var.opnsense_disk_size
    file_format  = "raw"
  }

  efi_disk {
    datastore_id = var.vm_datastore_id
    type         = "4m"
  }

  cdrom {
    enabled   = true
    file_id   = var.opnsense_iso_file_id
    interface = "ide3"
  }

  boot_order = ["scsi0", "ide3"]

  network_device {
    bridge = var.opnsense_wan_bridge
    model  = "virtio"
  }

  network_device {
    bridge = var.opnsense_lan_bridge
    model  = "virtio"
  }

  agent {
    enabled = false
  }

  operating_system {
    type = "other"
  }
}
