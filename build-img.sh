#!/bin/bash

output_path=$1
output_dir=$(dirname "$output_path")
output_file=$(basename "$output_path")

truncate --size=2G "${output_path}"
sgdisk --clear --new 1::+300M --typecode=1:ef00 --new 2::-0 --typecode=2:8304 "${output_path}"

loop_dev=/dev/loop123
sudo losetup --partscan "${loop_dev}" "${output_path}"
sudo mkfs.fat -F 32 "${loop_dev}p1"
sudo mkfs.ext4 "${loop_dev}p2"

sudo partprobe ${loop_dev}

sudo mount --mkdir "${loop_dev}p1" "${output_dir}/mount/boot"
sudo mount --mkdir "${loop_dev}p2" "${output_dir}/mount/img"
sudo mount --mkdir --bind "${output_dir}/mount/boot" "${output_dir}/mount/img/boot"
sudo pacstrap "${output_dir}/mount/img" base linux zram-generator openssh cloud-init cloud-guest-utils

sudo arch-chroot "${output_dir}/mount/img" /bin/bash << EOM
echo "[zram0]" > /etc/systemd/zram-generator.conf
ln --symbolic --force /usr/share/zoneinfo/UTC /etc/localtime
systemctl enable systemd-networkd.service systemd-resolved.service cloud-init.service cloud-final.service
sed --in-place --expression='s/^MODULES=(\(.*\))/MODULES=(\1 virtio-pci virtio-scsi)/' --expression='s/(\s/(/' /etc/mkinitcpio.conf
sed --in-place --expression='s/^HOOKS=(base\(.*\))/HOOKS=(base systemd\1)/' /etc/mkinitcpio.conf
mkinitcpio -P
bootctl install
echo "timeout 1" > /boot/loader/loader.conf
cat > "/boot/loader/entries/$(grep --perl-regexp --only-matching '^ID=\K.*' /etc/os-release | sed --expression='s/^"//' --expression='s/"$//').conf" << EOF
title $(grep --perl-regexp --only-matching '^PRETTY_NAME=\K.*' /etc/os-release | sed --expression='s/^"//' --expression='s/"$//')
linux /vmlinuz-linux
initrd /initramfs-linux.img
EOF
sed --in-place --expression='s/.*/uninitialized/' /etc/machine-id
echo "IMAGE_ID=${output_file}" >> /etc/os-release
echo "IMAGE_VERSION=$(date --utc --iso-8601=minutes)" >> /etc/os-release
EOM

sudo umount "${output_dir}/mount/img/boot" && sudo rmdir "${output_dir}/mount/img/boot"
sudo umount "${output_dir}/mount/boot" && sudo rmdir "${output_dir}/mount/boot"
sudo umount "${output_dir}/mount/img" && sudo rmdir "${output_dir}/mount/img" && sudo rmdir "${output_dir}/mount"

qemu-img convert -c -O qcow2 "${output_path}" "${output_path}.qcow2"
