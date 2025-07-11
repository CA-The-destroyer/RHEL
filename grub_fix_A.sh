#!/bin/bash
set -euo pipefail

echo "🔍 Mounting /boot/efi if needed..."
mount | grep /boot/efi || mount /dev/sda1 /boot/efi

echo "📁 Ensuring EFI directory exists..."
ls -l /boot/efi/EFI/RHEL || mkdir -p /boot/efi/EFI/RHEL

echo "⚙️ Installing GRUB bootloader..."
grub2-install --target=x86_64-efi \
  --efi-directory=/boot/efi \
  --bootloader-id=RHEL \
  --recheck --no-nvram --force

echo "🛠 Rebuilding GRUB configuration..."
grub2-mkconfig -o /boot/efi/EFI/RHEL/grub.cfg

echo "✅ GRUB install complete and config regenerated."
