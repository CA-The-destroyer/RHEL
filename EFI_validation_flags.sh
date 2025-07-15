#!/bin/bash
set -euo pipefail

echo "🔍 Checking EFI System Partition (ESP) and GRUB setup..."

# Detect EFI partition by mountpoint
EFI_MOUNT="/boot/efi"
EFI_DEV=$(findmnt -n -o SOURCE "$EFI_MOUNT" || true)

if [[ -z "$EFI_DEV" ]]; then
  echo "❌ EFI mount point not found at $EFI_MOUNT"
  exit 1
fi

# Strip /dev/ prefix and partition number
DISK="/dev/$(lsblk -no pkname "$EFI_DEV")"
PARTNUM=$(echo "$EFI_DEV" | grep -o '[0-9]*$')

echo "✅ EFI Partition Detected: $EFI_DEV"
echo "→ On Disk: $DISK Partition Number: $PARTNUM"

# Check partition flags
FLAGS=$(parted "$DISK" print | awk -v part="$PARTNUM" '$1 == part {print $7, $8}')
if [[ "$FLAGS" == *"boot"* && "$FLAGS" == *"esp"* ]]; then
  echo "✅ EFI partition has correct flags: boot, esp"
else
  echo "⚠️ EFI partition missing flags. Setting now..."
  parted "$DISK" set "$PARTNUM" boot on
  parted "$DISK" set "$PARTNUM" esp on
fi

# Check filesystem type
FSTYPE=$(blkid -s TYPE -o value "$EFI_DEV")
if [[ "$FSTYPE" != "vfat" ]]; then
  echo "❌ EFI partition is not FAT32 (vfat). Found: $FSTYPE"
  exit 1
else
  echo "✅ EFI partition filesystem is FAT32 (vfat)"
fi

# Check for GRUB EFI file
GRUB_PATH="$EFI_MOUNT/EFI/RHEL_new/grubx64.efi"
if [[ -f "$GRUB_PATH" ]]; then
  echo "✅ GRUB EFI file found at: $GRUB_PATH"
else
  echo "⚠️ GRUB EFI file not found at: $GRUB_PATH"
  read -rp "→ Reinstall GRUB to RHEL_new? (yes/no): " reinstall
  if [[ "$reinstall" == "yes" ]]; then
    grub2-install \
      --target=x86_64-efi \
      --efi-directory="$EFI_MOUNT" \
      --bootloader-id=RHEL_new \
      --recheck --no-nvram --force
  else
    echo "⏭ Skipping GRUB installation"
  fi
fi

# Regenerate grub.cfg
read -rp "→ Regenerate GRUB config now? (yes/no): " regen
if [[ "$regen" == "yes" ]]; then
  grub2-mkconfig -o "$EFI_MOUNT/EFI/RHEL_new/grub.cfg"
  echo "✅ GRUB config regenerated."
fi

echo "✅ ESP and GRUB validation complete."
