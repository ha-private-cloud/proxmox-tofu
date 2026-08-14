# Dedicated storage VM (not a Talos node): plain Debian, running an NFS
# server that backs the cluster's csi-driver-nfs StorageClass. Talos nodes'
# own disks are already fully allocated to Talos's own partitions, so
# cluster storage lives here instead of on the Talos VMs themselves.
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

  # type = "host": the synthetic "x86-64-v2-AES" type (used for the Talos
  # VMs) triggers a reproducible early-boot kernel panic on this Debian
  # cloud image (crashes identically in apparmor_file_permission every
  # time) , likely a BPF-JIT/CPU-feature mismatch AppArmor/seccomp hits
  # that Talos's minimal userspace never exercises. "host" passes the real
  # CPU through 1:1, which sidesteps it; fine since this is a single,
  # non-migrating Proxmox host.
  cpu {
    cores = var.nfs_vm_cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.nfs_vm_memory
  }

  # OS disk: imported from the Debian cloud image, then grown to the
  # configured size (the source image itself is only a few GB).
  # aio = "native": io_uring (the provider default) can corrupt data on
  # import on some LVM-thin setups, observed here as an early init crash.
  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    import_from  = proxmox_download_file.nfs_debian_cloud_image[each.value.node_name].id
    size         = var.nfs_os_disk_size
    file_format  = "raw"
    aio          = "native"
  }

  # Dedicated blank data disk exported over NFS. Formatted and mounted by
  # scripts/setup-nfs-server.sh (see README) , Tofu only provisions it.
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
      # Console-only fallback for finding this VM's DHCP IP (no easy way to
      # discover it otherwise , enabling the guest agent for this hung
      # waiting on the channel to attach, so this is the simpler path).
      password = random_password.nfs_console[each.key].result
    }
  }

  # Same VLAN tagging + explicit MAC scheme as the Talos VMs in vms.tf , see
  # the comment there. NFS storage moves onto the isolated cluster VLAN too,
  # since the Talos nodes mounting it are moving there.
  network_device {
    bridge      = var.network_bridge
    model       = "virtio"
    vlan_id     = var.cluster_vlan_id
    mac_address = format("02:00:00:00:%02x:%02x", floor(each.value.vm_id / 256), each.value.vm_id % 256)
  }

  agent {
    enabled = false
  }

  operating_system {
    type = "l26"
  }
}
