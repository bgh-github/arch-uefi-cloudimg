#!/bin/bash

output_path="${1}"
output_dir=$(dirname "${output_path}")
output_file=$(basename "${output_path}")

truncate --size=2G "${output_path}"
sgdisk --align-end --clear --new 0:0:+300M --typecode=0:ef00 --new 0:0:0 --typecode=0:8304 "${output_path}"

loop_dev=/dev/loop123
sudo losetup --partscan "${loop_dev}" "${output_path}"
sudo mkfs.fat -F 32 "${loop_dev}p1"
sudo mkfs.ext4 "${loop_dev}p2"
sudo partprobe "${loop_dev}"

sudo mount --mkdir -o umask=077 "${loop_dev}p1" "${output_dir}/mount/efi"
sudo mount --mkdir "${loop_dev}p2" "${output_dir}/mount/img"
sudo pacstrap "${output_dir}/mount/img" base
sudo arch-chroot "${output_dir}/mount/img" mkdir /efi
sudo mount --bind "${output_dir}/mount/efi" "${output_dir}/mount/img/efi"
sudo pacstrap "${output_dir}/mount/img" linux systemd-ukify zram-generator openssh cloud-init cloud-guest-utils gptfdisk

sudo arch-chroot "${output_dir}/mount/img" /bin/bash << EOF
rm /boot/initramfs-linux*.img
echo '[zram0]' > /etc/systemd/zram-generator.conf
systemd-firstboot --timezone=UTC
systemctl enable systemd-networkd.service systemd-resolved.service cloud-init.service cloud-final.service
sed --in-place --expression='s|\(^\MODULES=(\)\(.*\))$|\1\2 virtio_pci sr_mod)|' --expression='s|(\s|(|' --expression='s|\(^HOOKS=(base\)|\1 systemd|' /etc/mkinitcpio.conf
sed --in-place --expression='s|\(default_image=\)|#\1|' --expression='s|#\(default_uki=\)|\1|' --expression='s|#\(default_options=\)"\(.*\)"|\1"\2 --no-cmdline"|' --expression='s|\(fallback_image=\)|#\1|' --expression='s|#\(fallback_uki=\)|\1|' --expression='s|\(fallback_options=\)"\(.*\)"|\1"\2 --no-cmdline"|' /etc/mkinitcpio.d/linux.preset
bootctl install
mkinitcpio --allpresets
sed --in-place --expression='s|.*|uninitialized|' /etc/machine-id
echo "BUILD_ID=${output_file}-$(date --utc --iso-8601=minutes)" >> /etc/os-release
EOF

sudo umount "${output_dir}/mount/img/efi" && sudo rmdir "${output_dir}/mount/img/efi"
sudo umount "${output_dir}/mount/efi" && sudo rmdir "${output_dir}/mount/efi"
sudo umount "${output_dir}/mount/img" && sudo rmdir "${output_dir}/mount/img" && sudo rmdir "${output_dir}/mount"

qemu-img convert -c -O qcow2 "${output_path}" "${output_path}.qcow2"
