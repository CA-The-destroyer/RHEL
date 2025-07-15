#!/bin/bash
set -euo pipefail

VG="rootvg"  # Change if needed
declare -A LV_MOUNTS=(
  [rootlv]="/"
  [usrlv]="/usr"
  [varlv]="/var"
  [tmplv]="/tmp"
  [homelv]="/home"
)

echo "🔽 Pre-cleanup: Unmounting existing /mnt stack (if any)..."

# First attempt recursive unmount
if umount -R /mnt 2>/dev/null; then
  echo "✅ Recursive unmount succeeded"
else
  echo "⚠️ Recursive unmount failed, falling back to manual unmounts"
  for path in boot/efi boot usr var tmp home dev proc sys run; do
    umount -l "/mnt/$path" 2>/dev/null || true
  done
  umount -l /mnt 2>/dev/null || true
fi

echo "🧱 Starting clean remount of all partitions and volumes..."

# Mount root first
mount "/dev/${VG}/rootlv" /mnt

# Mount other LVs if they exist
for lv in "${!LV_MOUNTS[@]}"; do
  target="${LV_MOUNTS[$lv]}"
  if [[ "$target" == "/" ]]; then continue; fi
  if lvdisplay "/dev/${VG}/${lv}" &>/dev/null; then
    echo "📦 Mounting $lv → $target"
    mkdir -p "/mnt${target}"
    mount "/dev/${VG}/${lv}" "/mnt${target}"
  else
    echo "⏭ Skipping $lv (not found)"
  fi
done

# Mount /boot and /boot/efi
mount /dev/sdc2 /mnt/boot
mount /dev/sdc1 /mnt/boot/efi

# Bind system mounts
for fs in dev proc sys run; do
  mount --bind "/$fs" "/mnt/$fs"
done

echo "✅ All mounts ready for chroot"
echo "→ Run: chroot /mnt"
