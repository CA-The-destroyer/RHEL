#!/bin/bash
set -euo pipefail

echo "🔍 Have you mounted the correct points (/, /boot, /boot/efi, dev, proc, sys, run)?"
read -rp "→ Type yes to continue: " confirm

if [[ "$confirm" != "yes" ]]; then
  echo "❌ Mount points not confirmed. Exiting."
  exit 1
fi

echo "✅ Proceeding..."

# Define root LV
ROOT_DEV="/dev/mapper/rootvg_new-rootlv"

# Check if root LV exists
if [[ ! -e "$ROOT_DEV" ]]; then
  echo "❌ Root logical volume not found: $ROOT_DEV"
  exit 2
fi

# Extract current UUID
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV")
echo "→ Current root UUID: $ROOT_UUID"

# Prompt user to review /etc/fstab
echo "🧾 Please ensure /etc/fstab contains the correct UUID for /"
echo "→ Looking for: UUID=$ROOT_UUID"
echo "→ You can edit it now if needed (vi will open)"
read -rp "Would you like to review and edit /etc/fstab now? (yes/no): " editfstab

if [[ "$editfstab" == "yes" ]]; then
  vi /etc/fstab
  echo "✅ fstab reviewed."
fi

# Kernel detection
KERNEL_VER=$(ls /lib/modules | sort -V | tail -n1)
echo "→ Kernel detected: $KERNEL_VER"

INITRAMFS_PATH="/boot/initramfs-${KERNEL_VER}.img"
echo "🛠 Rebuilding initramfs with LVM support..."
dracut -f --add lvm --add-drivers "dm-mod" "$INITRAMFS_PATH" "$KERNEL_VER" -v

# Rebuild GRUB only after fstab and initramfs are ready
GRUB_CFG="/boot/efi/EFI/RHEL_new/grub.cfg"
echo "🔄 Regenerating GRUB config: $GRUB_CFG"
grub2-mkconfig -o "$GRUB_CFG"

# Final UUID check
if grep -q "$ROOT_UUID" "$GRUB_CFG"; then
  echo "✅ GRUB config now references correct root UUID."
else
  echo "⚠️ WARNING: GRUB config still does not reference expected UUID."
  echo "→ Please verify manually: grep root=UUID $GRUB_CFG"
fi

echo "✅ All done. Exit chroot and reboot when ready."
