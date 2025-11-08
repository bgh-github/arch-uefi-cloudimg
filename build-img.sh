#!/usr/bin/env bash

output_path="${1}"
output_dir=$(dirname "${output_path}")

truncate --size=2G "${output_path}"
echo -e 'label: gpt\n size=300MiB, type=uefi\n type=4f68bce3-e8cd-4db1-96e7-fbcaf984b709, attrs=59' | sfdisk "${output_path}"

loop_dev=$(sudo losetup --partscan --show --find "${output_path}")
sudo mkfs.fat -F 32 "${loop_dev}p1"
sudo mkfs.ext4 "${loop_dev}p2"

sudo mount --mkdir -o umask=077 "${loop_dev}p1" "${output_dir}/mount/efi"
sudo mount --mkdir "${loop_dev}p2" "${output_dir}/mount/img"
sudo pacstrap "${output_dir}/mount/img" base
sudo arch-chroot "${output_dir}/mount/img" mkdir /efi
sudo mount --bind "${output_dir}/mount/efi" "${output_dir}/mount/img/efi"
sudo pacstrap "${output_dir}/mount/img" linux systemd-ukify zram-generator openssh cloud-init

sudo arch-chroot "${output_dir}/mount/img" /bin/bash << EOF
rm /boot/initramfs-linux.img
echo '[zram0]' > /etc/systemd/zram-generator.conf
mkdir /etc/repart.d && echo -e '[Partition]\nType=root' > /etc/repart.d/grow-root.conf
systemd-firstboot --timezone=UTC
systemctl enable systemd-networkd.service systemd-resolved.service cloud-init-main.service cloud-final.service
sed --in-place --expression='/^MODULES=/s|()|(sr_mod)|' /etc/mkinitcpio.conf
sed --in-place --expression='/^default_image=/s|^|#|' --expression='/^#default_uki=/s|^#||' --expression='s|#\(default_options=\)"\(.*\)"|\1"\2 --no-cmdline"|' /etc/mkinitcpio.d/linux.preset
bootctl install
mkinitcpio --preset linux
sed --in-place --expression='s|.*|uninitialized|' /etc/machine-id
echo "BUILD_ID=$(basename "${output_path}")-$(date --utc --iso-8601=minutes)" >> /etc/os-release
EOF

sudo umount "${output_dir}/mount/img/efi" && sudo rmdir "${_}"
sudo umount "${output_dir}/mount/efi" && sudo rmdir "${_}"
sudo umount "${output_dir}/mount/img" && sudo rmdir "${_}" && sudo rmdir "${output_dir}/mount"

qemu-img convert -c -O qcow2 "${output_path}" "${output_path}.qcow2"
