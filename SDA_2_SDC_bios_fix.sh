#SDA to SDC bios part Fix

#!/bin/bash
set -euo pipefail

DISK="/dev/sdc"

echo "⚠️  This will DESTROY all data on $DISK. Continue? (yes/no)"
read -r CONFIRM
[[ "$CONFIRM" != "yes" ]] && { echo "Aborted."; exit 1; }

echo "🧹 Wiping partition table on $DISK..."
sgdisk --zap-all "$DISK"

echo "🧱 Creating new GPT partition layout..."
# 1: 200MiB EFI
sgdisk -n 1:1MiB:+200MiB -t 1:ef00 -c 1:"EFI System Partition" "$DISK"

# 2: 500MiB /boot
sgdisk -n 2:0:+500MiB -t 2:8300 -c 2:"boot" "$DISK"

# 3: 1MiB bios_grub
sgdisk -n 3:0:+1MiB -t 3:ef02 -c 3:"bios_grub" "$DISK"

# 4: remaining space LVM
sgdisk -n 4:0:0 -t 4:8e00 -c 4:"LVM" "$DISK"

partprobe "$DISK"
sleep 2

echo "💽 Formatting..."
mkfs.vfat -F32 "${DISK}1"
mkfs.xfs "${DISK}2"
# leave ${DISK}3 untouched
pvcreate "${DISK}4"

echo "✅ Partitioning complete."

echo "📎 Mounting for staging:"
mountpoint=/mnt
mkdir -p "$mountpoint"
mount /dev/mapper/rootvg-rootlv "$mountpoint"
mkdir -p "$mountpoint/boot"
mount "${DISK}2" "$mountpoint/boot"
mkdir -p "$mountpoint/boot/efi"
mount "${DISK}1" "$mountpoint/boot/efi"

echo "✅ Ready for chroot and GRUB installation."
