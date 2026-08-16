resource "proxmox_virtual_environment_vm" "opnsense" {
  name      = "opnsense"
  node_name = var.node_name
  vm_id     = var.opnsense_vm_id

  bios    = "ovmf"
  machine = "q35"

  # Single, non-migrating standalone host , passing the real CPU through
  # avoids any synthetic-CPU-type surprises (see ../tofu/nfs-storage.tf's
  # comment on the same tradeoff for the same reason).
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
    file_id   = var.opnsense_iso_file_id
    interface = "ide3"
  }

  # Boots from the installer ISO until OPNsense is installed to disk; scsi0
  # takes priority once it's bootable, so this is safe to leave as-is
  # rather than flipping it post-install.
  boot_order = ["scsi0", "ide3"]

  # WAN: physical NIC passthrough, not bridged through Proxmox.
  hostpci {
    device = "hostpci0"
    id     = var.opnsense_wan_pci_id
    pcie   = true
  }

  # LAN: virtio NIC on the shared LAN bridge.
  network_device {
    bridge = var.opnsense_lan_bridge
    model  = "virtio"
  }

  agent {
    enabled = false
  }

  # FreeBSD-based, not Linux.
  operating_system {
    type = "other"
  }
}
