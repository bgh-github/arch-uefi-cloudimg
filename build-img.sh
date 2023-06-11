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

sudo mount --mkdir "${loop_dev}p1" "${output_dir}/mount/boot"
sudo mount --mkdir "${loop_dev}p2" "${output_dir}/mount/img"
sudo mount --mkdir --bind "${output_dir}/mount/boot" "${output_dir}/mount/img/boot"
sudo pacstrap "${output_dir}/mount/img" base linux zram-generator openssh cloud-init cloud-guest-utils

sudo arch-chroot "${output_dir}/mount/img" /bin/bash << EOM
echo '[zram0]' > /etc/systemd/zram-generator.conf
ln --symbolic --force /usr/share/zoneinfo/UTC /etc/localtime
systemctl enable systemd-networkd.service systemd-resolved.service cloud-init.service cloud-final.service
sed --in-place --expression='s|\(^\MODULES=(\)\(.*\))|\1\2 virtio-pci virtio-scsi)|' --expression='s|(\s|(|' /etc/mkinitcpio.conf
sed --in-place --expression='s|\(^HOOKS=(base\)|\1 systemd|' /etc/mkinitcpio.conf
mkinitcpio --allpresets
bootctl install
cat > "/boot/loader/entries/$(grep --perl-regexp --only-matching '^ID=\K.*' /etc/os-release).conf" << EOF
title $(grep --perl-regexp --only-matching '^PRETTY_NAME="\K[^"]*' /etc/os-release)
linux /vmlinuz-linux
initrd /initramfs-linux.img
EOF
sed --in-place --expression='s|.*|uninitialized|' /etc/machine-id
echo "BUILD_ID=${output_file}-$(date --utc --iso-8601=minutes)" >> /etc/os-release
EOM

sudo umount "${output_dir}/mount/img/boot" && sudo rmdir "${output_dir}/mount/img/boot"
sudo umount "${output_dir}/mount/boot" && sudo rmdir "${output_dir}/mount/boot"
sudo umount "${output_dir}/mount/img" && sudo rmdir "${output_dir}/mount/img" && sudo rmdir "${output_dir}/mount"

qemu-img convert -c -O qcow2 "${output_path}" "${output_path}.qcow2"
