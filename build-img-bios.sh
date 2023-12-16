#!/bin/bash

output_path="${1}"
output_dir=$(dirname "${output_path}")
output_file=$(basename "${output_path}")

truncate --size=2G "${output_path}"
sgdisk --align-end --clear --new 0:0:+1M --typecode=0:ef02 --new 0:0:0 --typecode=0:8304 "${output_path}"

loop_dev=/dev/loop123
sudo losetup --partscan "${loop_dev}" "${output_path}"
sudo mkfs.ext4 "${loop_dev}p2"
sudo partprobe "${loop_dev}"

sudo mount --mkdir "${loop_dev}p2" "${output_dir}/mount/img"
sudo pacstrap "${output_dir}/mount/img" base linux zram-generator openssh cloud-init cloud-guest-utils grub

sudo arch-chroot "${output_dir}/mount/img" /bin/bash << EOF
echo '[zram0]' > /etc/systemd/zram-generator.conf
systemd-firstboot --timezone=UTC
systemctl enable systemd-networkd.service systemd-resolved.service cloud-init.service cloud-final.service
sed --in-place --expression='s|\(^\MODULES=(\)\(.*\))$|\1\2 virtio_pci sr_mod)|' --expression='s|(\s|(|' --expression='s|\(^HOOKS=(base\)|\1 systemd|' /etc/mkinitcpio.conf
mkinitcpio --allpresets
grub-install --target=i386-pc "${loop_dev}"
grub-mkconfig --output=/boot/grub/grub.cfg
sed --in-place --expression='s|.*|uninitialized|' /etc/machine-id
echo "BUILD_ID=${output_file}-$(date --utc --iso-8601=minutes)" >> /etc/os-release
EOF

sudo umount "${output_dir}/mount/img" && sudo rmdir "${output_dir}/mount/img" && sudo rmdir "${output_dir}/mount"
