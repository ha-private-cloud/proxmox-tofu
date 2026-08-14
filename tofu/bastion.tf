# CI bastion: plain openSUSE Leap VM that hosts what
# GitHub Actions self-hosted runners for the app repos actually run
# against , the kubeconfig, each repo's gitignored terraform.tfvars, and
# ~/.config/cluster-cli/config.toml. Runners poll GitHub outbound, 
# so nothing about this needs to be reachable from the internet inbound
resource "proxmox_download_file" "bastion_cloud_image" {
  content_type = "import"
  datastore_id = var.iso_datastore_id
  node_name    = var.bastion_node_name

  url       = var.bastion_cloud_image_url
  file_name = "opensuse-leap-16.0-x86_64-cloud.qcow2"

  overwrite = false
}

resource "random_password" "bastion_console" {
  length  = 20
  special = false
}

resource "proxmox_virtual_environment_vm" "bastion" {
  name      = "ci-bastion"
  node_name = var.bastion_node_name
  vm_id     = var.bastion_vm_id

  bios    = "ovmf"
  machine = "q35"

  cpu {
    cores = var.bastion_cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.bastion_memory
  }

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    import_from  = proxmox_download_file.bastion_cloud_image.id
    size         = var.bastion_disk_size
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
      username = var.bastion_admin_username
      keys     = [trimspace(file(pathexpand(var.bastion_ssh_public_key_path)))]
      # Console-only fallback for finding this VM's DHCP IP , same reasoning
      # as nfs-storage.tf's random_password.nfs_console.
      password = random_password.bastion_console.result
    }
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  agent {
    enabled = false
  }

  operating_system {
    type = "l26"
  }
}
