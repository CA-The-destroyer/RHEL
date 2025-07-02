#!/bin/bash

set -euo pipefail

echo "[+] Scanning sdd partitions..."
BOOT_EFI_UUID=$(blkid -t TYPE=vfat -s UUID -o value /dev/sdd1)
BOOT_UUID=$(blkid -t TYPE=ext4 -s UUID -o value /dev/sdd2)
ROOT_UUID=$(blkid -t TYPE=ext4 -s UUID -o value /dev/sdd3)

echo "[+] Mounting /dev/sdd3 as /mnt..."
mount /dev/sdd3 /mnt
mount /dev/sdd2 /mnt/boot
mount /dev/sdd1 /mnt/boot/efi

echo "[+] Binding system directories..."
for d in dev proc sys run; do
  mount --bind /$d /mnt/$d
done

echo "[+] Entering chroot..."
chroot /mnt /bin/bash <<'EOC'

echo "[+] Reinstalling GRUB to EFI on /dev/sdd1..."
grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=redhat --recheck --no-nvram

echo "[+] Generating new grub.cfg..."
grub2-mkconfig -o /boot/grub2/grub.cfg

echo "[+] Copying fallback BOOTX64.EFI..."
mkdir -p /boot/efi/EFI/BOOT
cp /boot/efi/EFI/redhat/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI

echo "[+] Creating EFI boot entry..."
efibootmgr -c -d /dev/sdd -p 1 -L "RHEL-Fixed" -l '\EFI\redhat\grubx64.efi'

EOC

echo "[+] Listing EFI boot entries..."
efibootmgr -v

echo "[+] Done. You may now unmount and reboot."
