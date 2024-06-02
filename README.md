# Arch UEFI Cloud Image (arch-uefi-cloudimg)

A (unofficial) minimal, [cloud-init](https://cloudinit.readthedocs.io) enabled [Arch Linux](https://archlinux.org) virtual machine image build for UEFI booting on latest generation VM hardware.

The image targets "modern" specification [Proxmox VE](https://www.proxmox.com/proxmox-ve) (or more generally [QEMU](https://www.qemu.org)/KVM) VM hardware. That is, QEMU VMs configured with UEFI (OVMF) boot, Q35 chipset, paravirtualised VirtIO storage and network etc.

## Download

**[Image Download](https://cdn.bgh.io/arch-uefi-cloudimg.qcow2)** (compressed qcow2 format)  
**[Checksum Download](https://cdn.bgh.io/arch-uefi-cloudimg.qcow2.sha384sum)** to verify

```bash
img_file=arch-uefi-cloudimg.qcow2
# img_file=arch-uefi-cloudimg.raw

cd "${HOME}/Downloads" || exit
curl --remote-name "https://cdn.bgh.io/${img_file}"
curl --remote-name "https://cdn.bgh.io/${img_file}.sha384sum"

sha384sum --check "${img_file}.sha384sum"
```

[![Refresh image](../../actions/workflows/main.yml/badge.svg)](../../actions/workflows/main.yml)

The above GitHub Actions workflow automatically refreshes the image around midnight UTC+0 each day. Downloads will remain openly available so long as CDN bandwidth costs don't get out of hand.

> [!WARNING]
> It mostly goes without saying, but a quick disclaimer: files are provided as-is for non-mission-critical use. They should not be relied upon, and at times may be broken

## Local Build

It should also be possible to generate the image locally by executing `./build-img.sh <output_path>` on an Arch-based machine. For example, `./build-img.sh /tmp/arch-uefi-cloudimg`.

The machine running the build must have internet connectivity and the following packages installed at a minimum - `gptfdisk`, `sudo`/`base-devel`, `dosfstools`, `arch-install-scripts`, `qemu-img`.

## What's Included

In short, not much. And that's kind of the idea.

In the Arch [spirit](https://wiki.archlinux.org/title/Arch_Linux#Principles) of simplicity and minimalism, the only packages installed out of the box with arch-uefi-cloudimg are `base`, `linux`, `systemd-ukify`, `zram-generator`, `openssh`, `cloud-init`, `cloud-guest-utils`, and `gptfdisk` (and their dependencies). The main reason arch-uefi-cloudimg exists is to solve a bootstrapping problem. Its job is really to do just enough to facilitate VM boot and early initialisation, at which point a full configuration management solution would take over.

Typically, the VM provisioning process would go something like

1. Use cloud-init to prime the absolute essentials for the environment, such as network configuration, SSH keys, and any management agents
2. Once the VM is in a manageable state, have a configuration management tool handle subsequent setup

In this way, arch-uefi-cloudimg is intentionally a blank canvas.

The slightly opinionated part is perhaps the eschewment of "legacy" technologies and including + enabling `zram-generator`. On balance, this seemed reasonable with consensus on the age-old "to swap or not to swap" question appearing to converge towards zram (see [Fedora change](https://fedoraproject.org/wiki/Changes/SwapOnZRAM)), zram being relatively trivial to disable post-provisioning, no upfront partitioning implications, and the assumption modern virtualised workloads would be flash storage backed.

## Running

With the image downloaded (and verified), it's now time to spin up a VM. Command line examples provided below for Proxmox VE and local QEMU. These same principles can be adapted to various deployment tooling/APIs as appropriate.

<details>
  <summary>Proxmox VE</summary>

  Transfer image and `cloud-config.yml` file containing any custom cloud-init vendor/user data to PVE host

  ```bash
  pve=user@pve.lan.example.com

  scp arch-uefi-cloudimg.qcow2 "${pve}:/var/lib/vz/images/arch-uefi-cloudimg.qcow2"
  scp cloud-config.yml "${pve}:/var/lib/vz/snippets/cloud-config.yml"
  ```

  Use PVE host shell to create VM, set cloud-init values, import image, and boot

  ```bash
  storage=local-zfs

  vmid=123
  name=example
  ip=10.0.0.123/24
  gw=10.0.0.1
  user=configmgmt
  cat > /tmp/sshkeys << 'EOF'
  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIKk+Dj3QV8CYQp/JIL9JQJEfMLOFW7TpxVJEIq0BrUR configmgmt@lan.example.com
  sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIBEtFzO7x6APTSMQFf8vN0/+X1YgH+5BxRr58CEz2/fAAAAAC3NzaDpleGFtcGxl
  EOF

  qm create "${vmid}" \
    --name "${name}" \
    --cpu host \
    --cores 2 \
    --memory 2048 \
    --ostype l26 \
    --machine q35 \
    --bios ovmf \
    --efidisk0 "${storage}:0" \
    --scsihw virtio-scsi-pci \
    --scsi0 "${storage}:0,import-from=/var/lib/vz/images/arch-uefi-cloudimg.qcow2" \
    --bootdisk scsi0 \
    --boot c \
    --net0 virtio,bridge=vmbr0,tag=3 \
    --vga qxl \
    --agent 1 \
    --sata0 "${storage}:cloudinit" \
    --ipconfig0 "ip=${ip},gw=${gw}" \
    --ciuser "${user}" \
    --sshkeys /tmp/sshkeys \
    --cicustom "vendor=local:snippets/cloud-config.yml"
    #--nameserver and --searchdomain automatically inherit host settings if not specified

  qm resize "${vmid}" scsi0 20G
  qm start "${vmid}"
  ```

</details>

<details>
  <summary>Local QEMU</summary>

  Generate cloud-init NoCloud ISO

  ```bash
  touch meta-data

  cat > user-data << 'EOF'
  #cloud-config
  hostname: example
  users:
    - name: configmgmt
      passwd: $6$cGjycsOkR1KQFQXW$MyZrZZD8o39wILwMcw8GZOGXt0nII9jHJ4eUcDrCra3gX5zAFYS7j5FoUQ4OT1b4cQlvC06y17daz8C4MWWgh1 # example
      lock_passwd: false
      sudo: ALL=(ALL) NOPASSWD:ALL
  EOF

  <<comment
  # Default QEMU user networking (SLIRP) guest settings, IP=10.0.2.15/24, GW=10.0.2.2 (host), DNS=10.0.2.3
  # Alternatively, if setting statically through cloud-init, perhaps using a bridged tap interface
  cat > network-config << EOF
  version: 2
  ethernets:
    enp0s2:
      addresses:
        - 10.0.0.123/24
      gateway4: 10.0.0.1
      nameservers:
        addresses:
          - 10.0.0.2
        search:
          - lan.example.com
  EOF
  comment

  cp cloud-config.yml vendor-data

  xorriso -as genisoimage -output cloud-init.iso -volid CIDATA -joliet -rock meta-data user-data vendor-data #network-config
  ```

  Run VM

  ```bash
  qemu-img resize arch-uefi-cloudimg.qcow2 20G
  qemu-system-x86_64 \
    -enable-kvm \
    -cpu host \
    -smp cores=2 \
    -m 2G \
    -machine q35 \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/ovmf/x64/OVMF_CODE.fd \
    -device virtio-scsi-pci \
    -device scsi-hd,drive=scsi0 \
    -drive file=arch-uefi-cloudimg.qcow2,if=none,id=scsi0 \
    -nic user,model=virtio-net-pci \
    -cdrom cloud-init.iso
  ```

</details>

In either case

* cloud-init should take care of growing the root partition into available space
* `cloud-config.yml` may include something like

  ```yaml
  #cloud-config
  locale: en_US.UTF-8
  timezone: US/Eastern
  packages: qemu-guest-agent
  runcmd:
    - pacman-key --init
    - systemctl enable --now qemu-guest-agent
  ```

## Related Projects

### [Arch-boxes](https://gitlab.archlinux.org/archlinux/arch-boxes)

The official source of cloud-ready Arch VM images. This was the first thing I turned up in the search for a ready to run Arch cloud image.

Testing, I discovered the images were only BIOS compatible and wouldn't boot on my chosen VM hardware.

Finding an [issue](https://gitlab.archlinux.org/archlinux/arch-boxes/-/issues/141) about adding hybrid BIOS+UEFI support, I set out to see if this was something I could tackle. Eventually coming to the realisation that, given my requirements, the added complexity to maintain legacy BIOS support and fiddling with hybrid GRUB configuration (when simpler UEFI-only boot loader alternatives like systemd-boot exist) etc. wasn't something I wanted to pursue.

### [Arch Installer](https://github.com/archlinux/archinstall)

Aka the optional `archinstall` installer included on Arch media. It supports guided installation as well as automation through configuration files and a Python library.

If it hadn't of been for archinstall I mightn't have got my original start with Arch. While very useful in guided install scenarios, experimenting with archinstall I increasingly felt it was a bit too "heavy", and the various options not really necessary for building a basic cloud image. I did also encounter an inconsistency here or there with configuration files not behaving as expected.

### [mkosi](https://github.com/systemd/mkosi)

A utility under the systemd project banner used to create custom operating system images.

I stumbled upon this very late just prior to wrapping up work on arch-uefi-cloudimg. The tool appears to provide a high degree of flexibility if the goal is to build images for several OS flavours. Another plus it being built with an eye towards systemd-nspawn containers and secure boot. It also appears to share a similar ["legacy-free"](https://0pointer.net/blog/mkosi-a-tool-for-generating-os-images.html) philosophy to arch-uefi-cloudimg.

While yet to properly explore mkosi, I'd like to think arch-uefi-cloudimg still has its place in striking a balance between aligning to the official ArchWiki [Installation guide](https://wiki.archlinux.org/title/installation_guide) and doing what's necessary to automate modern cloud-ready Arch Linux VM image creation.

## BIOS

The unfortunate reality is many cloud/VPS providers still only support legacy BIOS boot.

For these situations, the rather paradoxically named arch-uefi-cloudimg-bios build is available. This variant includes a minimal set of changes to partitioning etc. and uses GRUB as the boot loader.

```bash
img_file=arch-uefi-cloudimg-bios.raw
# img_file=arch-uefi-cloudimg-bios.raw.gz

cd "${HOME}/Downloads" || exit
curl --remote-name "https://cdn.bgh.io/${img_file}"
curl --remote-name "https://cdn.bgh.io/${img_file}.sha384sum"

sha384sum --check "${img_file}.sha384sum"
```

[![Refresh image - BIOS](../../actions/workflows/refresh-image-bios.yml/badge.svg)](../../actions/workflows/refresh-image-bios.yml)
