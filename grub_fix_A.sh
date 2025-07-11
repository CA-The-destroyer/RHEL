#!/bin/bash
set -euo pipefail

BOOTID="RHEL_new"

echo "🔍 Mounting /boot/efi if needed..."
mount | grep -q /boot/efi || mount /dev/sda1 /boot/efi

echo "📁 Ensuring EFI directory exists..."
mkdir -p "/boot/efi/EFI/$BOOTID"

echo "⚙️ Installing GRUB with bootloader ID: $BOOTID"
grub2-install --target=x86_64-efi \
  --efi-directory=/boot/efi \
  --bootloader-id="$BOOTID" \
  --recheck --no-nvram --force

echo "🛠 Rebuilding GRUB configuration..."
grub2-mkconfig -o "/boot/efi/EFI/$BOOTID/grub.cfg"

echo "✅ GRUB installed as $BOOTID and config written to /boot/efi/EFI/$BOOTID/grub.cfg"
