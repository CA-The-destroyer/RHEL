#!/usr/bin/env bash
# Post_DD_Fstab_chk.sh — Interactive fstab updater after dd clone

set -euo pipefail

# 1️⃣ Ensure running as root
if [[ $EUID -ne 0 ]]; then
  echo "✋ Please run as root."
  exit 1
fi

# 2️⃣ Show current block devices
echo "Current block devices:"
lsblk
echo

# 3️⃣ Prompt for key inputs
read -rp "Enter the target disk (e.g. /dev/sdc): " TARGET_DISK
read -rp "Enter the old VG name (e.g. rootvg): " OLD_VG
read -rp "Enter the new VG name (e.g. rootvg_new): " NEW_VG

# 4️⃣ Define paths
ROOT_LV="/dev/mapper/${NEW_VG}-rootlv"
FSTAB="/mnt/etc/fstab"

# 5️⃣ Validate the root LV exists
if [[ ! -b ${ROOT_LV} ]]; then
  echo "❌ Block device ${ROOT_LV} not found. Aborting."
  exit 1
fi

# 6️⃣ Mount the new root LV
echo "🔧 Mounting ${ROOT_LV} → /mnt"
mount "${ROOT_LV}" /mnt

# 7️⃣ Backup & update fstab
echo "💾 Backing up fstab → ${FSTAB}.bak"
cp "${FSTAB}" "${FSTAB}.bak"

echo "✏️  Updating fstab entries"
sed -i \
  -e "s#/dev/mapper/${OLD_VG}-#/dev/mapper/${NEW_VG}-#g" \
  -e "s/[[:space:]]xfs[[:space:]]/ ext4 /g" \
  "${FSTAB}"

# 8️⃣ Cleanup mount
echo "🧹 Unmounting ${ROOT_LV}"
umount -lR /mnt

echo "✅ fstab updated."

# 9️⃣ Prompt for shutdown
read -rp "Would you like to shut down now? [y/N]: " SHUTDOWN
if [[ "$SHUTDOWN" =~ ^[Yy] ]]; then
  echo "🔒 Shutting down system..."
  shutdown -h 0
else
  echo "💡 Remember to run 'shutdown -h 0' when you’re ready."
fi
