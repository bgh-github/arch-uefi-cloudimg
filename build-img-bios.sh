#!/bin/bash

output_path="${1}"
output_dir=$(dirname "${output_path}")
output_file=$(basename "${output_path}")

truncate --size=2G "${output_path}"
sgdisk --clear --new 0:0:+1M --typecode=0:ef02 --new 0:0:0 --typecode=0:8304 "${output_path}"

loop_dev=/dev/loop123
sudo losetup --partscan "${loop_dev}" "${output_path}"
sudo mkfs.ext4 "${loop_dev}p2"
sudo partprobe "${loop_dev}"

sudo mount --mkdir "${loop_dev}p2" "${output_dir}/mount/img"
sudo pacstrap "${output_dir}/mount/img" base linux zram-generator openssh cloud-init cloud-guest-utils grub

sudo arch-chroot "${output_dir}/mount/img" /bin/bash << EOM
echo "[zram0]" > /etc/systemd/zram-generator.conf
ln --symbolic --force /usr/share/zoneinfo/UTC /etc/localtime
systemctl enable systemd-networkd.service systemd-resolved.service cloud-init.service cloud-final.service
sed --in-place --expression='s/^MODULES=(\(.*\))/MODULES=(\1 virtio-pci virtio-scsi)/' --expression='s/(\s/(/' /etc/mkinitcpio.conf
sed --in-place --expression='s/^HOOKS=(base\(.*\))/HOOKS=(base systemd\1)/' /etc/mkinitcpio.conf
mkinitcpio --allpresets
grub-install --target=i386-pc "${loop_dev}"
grub-mkconfig --output=/boot/grub/grub.cfg
sed --in-place --expression='s/.*/uninitialized/' /etc/machine-id
echo "BUILD_ID=${output_file}-$(date --utc --iso-8601=minutes)" >> /etc/os-release
sed --expression='s/if not check_route(url):/#if not check_route(url):/' --expression='/if not check_route(url):/{n;s/continue/#continue/g}' /usr/lib/python3.10/site-packages/cloudinit/sources/helpers/vultr.py
EOM

sudo umount "${output_dir}/mount/img" && sudo rmdir "${output_dir}/mount/img" && sudo rmdir "${output_dir}/mount"
