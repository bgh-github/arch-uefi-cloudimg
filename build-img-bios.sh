#!/bin/bash

output_path="${1}"
output_dir=$(dirname "${output_path}")
output_file=$(basename "${output_path}")

truncate --size=2G "${output_path}"
echo -e 'label: gpt\n size=1MiB, type=21686148-6449-6e6f-744e-656564454649\n type=4f68bce3-e8cd-4db1-96e7-fbcaf984b709, attrs=59' | sfdisk "${output_path}"

loop_dev=/dev/loop123
sudo losetup --partscan "${loop_dev}" "${output_path}"
sudo mkfs.ext4 "${loop_dev}p2"

sudo mount --mkdir "${loop_dev}p2" "${output_dir}/mount/img"
sudo pacstrap "${output_dir}/mount/img" base linux zram-generator openssh cloud-init grub

sudo arch-chroot "${output_dir}/mount/img" /bin/bash << EOF
echo '[zram0]' > /etc/systemd/zram-generator.conf
mkdir /etc/repart.d && echo -e '[Partition]\nType=root' > /etc/repart.d/grow-root.conf
systemd-firstboot --timezone=UTC
systemctl enable systemd-networkd.service systemd-resolved.service cloud-init-main.service cloud-final.service
sed --in-place --expression='s|\(^\MODULES=\).*|\1(virtio_pci sr_mod)|' --expression='s|\(^HOOKS=(base\)|\1 systemd|' --expression='/^HOOKS=/s| udev||; /^HOOKS=/s| keymap||; /^HOOKS=/s| consolefont||' /etc/mkinitcpio.conf
mkinitcpio --allpresets
grub-install --target=i386-pc "${loop_dev}"
grub-mkconfig --output=/boot/grub/grub.cfg
sed --in-place --expression='s|.*|uninitialized|' /etc/machine-id
echo "BUILD_ID=${output_file}-$(date --utc --iso-8601=minutes)" >> /etc/os-release
EOF

sudo umount "${output_dir}/mount/img" && sudo rmdir "${output_dir}/mount/img" && sudo rmdir "${output_dir}/mount"
