#!/bin/bash
set -euo pipefail

echo "🔍 Dracut Validation: Checking environment for safe initramfs regeneration"
echo

# 1. Verify kernel module directories exist
echo "📁 Kernel module directories under /lib/modules:"
if [[ ! -d /lib/modules ]]; then
  echo "❌ /lib/modules not found — you're not in a proper system or chroot."
  exit 1
fi

kernel_versions=$(ls -1 /lib/modules | sort -V)
latest_kernel=$(echo "$kernel_versions" | tail -n1)
echo "$kernel_versions" | sed 's/^/  └─ /'
echo "✅ Latest detected kernel: $latest_kernel"
echo

# 2. Check for kernel and initramfs in /boot
echo "📂 Verifying /boot contents for matching kernel/initramfs..."
vmlinuz_path="/boot/vmlinuz-$latest_kernel"
initramfs_path="/boot/initramfs-$latest_kernel.img"

[[ -f "$vmlinuz_path" ]] && echo "✅ Found kernel: $vmlinuz_path" || echo "❌ MISSING: $vmlinuz_path"
[[ -f "$initramfs_path" ]] && echo "✅ Found initramfs: $initramfs_path" || echo "⚠️ MISSING: $initramfs_path"
echo

# 3. Validate chroot environment (basic mounts)
echo "🔗 Verifying critical system mounts inside chroot:"
for d in /proc /sys /dev /run; do
  if mountpoint -q "$d"; then
    echo "✅ $d is mounted"
  else
    echo "❌ $d is NOT mounted — bind-mount it before running dracut"
  fi
done
echo

# 4. Confirm dracut availability
echo "📦 Verifying dracut availability:"
if ! command -v dracut >/dev/null 2>&1; then
  echo "❌ dracut not found in this environment"
  exit 1
fi
dracut --version
echo

# 5. Dry-run dracut to validate functionality
echo "🧪 Performing DRY-RUN initramfs generation check..."
dryrun_path="/tmp/initramfs-dryrun.img"
if dracut --dry-run --force "$dryrun_path" "$latest_kernel"; then
  echo "✅ Dry-run successful — dracut is working correctly"
else
  echo "❌ Dracut dry-run failed — possible missing modules or broken kernel"
  exit 1
fi
echo

echo "🎯 Ready to regenerate all initramfs images:"
echo "    dracut --regenerate-all --force -v"
