#!/bin/bash
set -euo pipefail

echo "🔍 Validating GRUB configuration against /boot contents..."

# Detect latest kernel
latest_kernel=$(ls -1 /boot/vmlinuz-* | sed 's/.*vmlinuz-//' | sort -V | tail -n1)
echo "✅ Latest kernel version: $latest_kernel"

# Check that initramfs exists
initramfs_path="/boot/initramfs-$latest_kernel.img"
if [[ -f "$initramfs_path" ]]; then
  echo "✅ Matching initramfs found: $initramfs_path"
else
  echo "❌ Missing initramfs for kernel $latest_kernel"
  exit 1
fi

# Find GRUB config
grub_cfg="/boot/efi/EFI/RHEL/grub.cfg"
if [[ ! -f "$grub_cfg" ]]; then
  echo "❌ GRUB config not found at $grub_cfg"
  echo "Looking for alternate GRUB configs..."
  grub_cfg=$(find /boot/efi/EFI -name grub.cfg | head -n1)
  [[ -z "$grub_cfg" ]] && { echo "❌ No grub.cfg found under /boot/efi"; exit 1; }
  echo "⚠️ Using alternate GRUB config: $grub_cfg"
fi

# Check if grub.cfg references the correct kernel/initramfs
echo
echo "🔍 Scanning $grub_cfg for kernel and initramfs..."
match_kernel=$(grep "vmlinuz-$latest_kernel" "$grub_cfg" || true)
match_initrd=$(grep "initramfs-$latest_kernel" "$grub_cfg" || true)

if [[ -n "$match_kernel" && -n "$match_initrd" ]]; then
  echo "✅ grub.cfg is already referencing the correct kernel and initramfs."
  exit 0
else
  echo "⚠️ grub.cfg is outdated. Fixing..."
  grub2-mkconfig -o "$grub_cfg"
  echo "✅ GRUB config regenerated successfully."
fi
