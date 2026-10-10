resource "random_password" "nfs_console" {
  for_each = var.nfs_instances

  length  = 20
  special = false
}

resource "proxmox_download_file" "nfs_debian_cloud_image" {
  for_each = toset([for n in var.nfs_instances : n.node_name])

  content_type = "import"
  datastore_id = var.iso_datastore_id
  node_name    = each.key

  url       = var.nfs_debian_cloud_image_url
  file_name = "debian-12-generic-amd64.qcow2"

  overwrite = false
}

resource "proxmox_virtual_environment_vm" "nfs" {
  for_each = var.nfs_instances

  name      = each.key
  node_name = each.value.node_name
  vm_id     = each.value.vm_id

  bios    = "ovmf"
  machine = "q35"

  cpu {
    cores = var.nfs_vm_cpu_cores
    # x86-64-v2-AES kernel-panics the Debian cloud image at boot.
    type = "host"
  }

  memory {
    dedicated = var.nfs_vm_memory
  }

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    import_from  = proxmox_download_file.nfs_debian_cloud_image[each.value.node_name].id
    size         = var.nfs_os_disk_size
    file_format  = "raw"
    aio          = "native"
  }

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi1"
    size         = var.nfs_data_disk_size
    file_format  = "raw"
    aio          = "native"
  }

  efi_disk {
    datastore_id = var.vm_datastore_id
    type         = "4m"
  }

  initialization {
    datastore_id = var.vm_datastore_id

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      username = var.nfs_admin_username
      keys     = [trimspace(file(pathexpand(var.nfs_ssh_public_key_path)))]
      password = random_password.nfs_console[each.key].result
    }
  }

  network_device {
    bridge      = var.network_bridge
    model       = "virtio"
    mac_address = format("02:00:00:00:%02x:%02x", floor(each.value.vm_id / 256), each.value.vm_id % 256)
  }

  agent {
    enabled = false
  }

  operating_system {
    type = "l26"
  }
}
