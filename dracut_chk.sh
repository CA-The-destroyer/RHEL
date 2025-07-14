#!/bin/bash
set -euo pipefail

echo "🔍 Have you mounted the correct points (/, /boot, /boot/efi, dev, proc, sys, run)?"
read -rp "→ Type yes to continue: " confirm

if [[ "$confirm" != "yes" ]]; then
  echo "❌ Mount points not confirmed. Exiting."
  exit 1
fi

echo "✅ Proceeding with initramfs validation..."

# Detect latest kernel
KERNEL_VER=$(ls /lib/modules | sort -V | tail -n1)
echo "→ Kernel detected: $KERNEL_VER"

# Check if initramfs exists
INITRAMFS_PATH="/boot/initramfs-${KERNEL_VER}.img"
if [[ -f "$INITRAMFS_PATH" ]]; then
  echo "✅ Found existing initramfs: $INITRAMFS_PATH"
else
  echo "⚠️ No initramfs found for $KERNEL_VER. Will create new one."
fi

# Rebuild initramfs with LVM and DM support
echo "🛠 Rebuilding initramfs with LVM support..."
dracut -f --add lvm --add-drivers "dm-mod" "$INITRAMFS_PATH" "$KERNEL_VER" -v

# Validate root UUID
ROOT_DEV="/dev/mapper/rootvg_new-rootlv"
if [[ ! -e "$ROOT_DEV" ]]; then
  echo "❌ Root logical volume not found: $ROOT_DEV"
  exit 2
fi

ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV")
echo "→ Root UUID: $ROOT_UUID"

GRUB_CFG="/boot/efi/EFI/RHEL_new/grub.cfg"
echo "🔍 Checking GRUB config at $GRUB_CFG"

if grep -q "$ROOT_UUID" "$GRUB_CFG"; then
  echo "✅ GRUB config already uses correct root UUID."
else
  echo "❌ GRUB config does NOT reference correct root UUID. Regenerating..."
  grub2-mkconfig -o "$GRUB_CFG"
fi

echo "✅ All done. You may now exit chroot and reboot."
