#!/bin/bash
set -euo pipefail

echo "🔍 Dracut Validation and Regeneration Script"

# 1. Verify /lib/modules exists
echo
echo "📁 Checking /lib/modules..."
if [[ ! -d /lib/modules ]]; then
  echo "❌ /lib/modules not found — are you in chroot or missing kernel modules?"
  exit 1
fi

kernel_versions=$(ls -1 /lib/modules | sort -V)
latest_kernel=$(echo "$kernel_versions" | tail -n1)
echo "$kernel_versions" | sed 's/^/  └─ /'
echo "✅ Latest kernel: $latest_kernel"
echo

# 2. Check /boot kernel and initramfs
vmlinuz="/boot/vmlinuz-$latest_kernel"
initramfs="/boot/initramfs-$latest_kernel.img"

echo "📂 Checking /boot files:"
[[ -f "$vmlinuz" ]] && echo "✅ $vmlinuz found" || { echo "❌ $vmlinuz missing"; exit 1; }
[[ -f "$initramfs" ]] && echo "✅ $initramfs found" || echo "⚠️ $initramfs missing (will be regenerated)"
echo

# 3. Required mount points
echo "🔗 Validating chroot mount points:"
MOUNTS_OK=true
for d in /proc /sys /dev /run; do
  if mountpoint -q "$d"; then
    echo "✅ $d is mounted"
  else
    echo "❌ $d is not mounted"
    MOUNTS_OK=false
  fi
done

if [[ "$MOUNTS_OK" == false ]]; then
  echo "💣 Missing required system mounts — please bind /proc, /sys, /dev, /run"
  exit 1
fi

# 4. Check dracut availability
echo
echo "📦 Checking for dracut..."
if ! command -v dracut &>/dev/null; then
  echo "❌ dracut not found — install it in this environment"
  exit 1
fi

dracut --version
echo

# 5. Run dry-run check
echo "🧪 Running dry-run to validate dracut build..."
if dracut --dry-run --force /tmp/initramfs-dryrun.img "$latest_kernel"; then
  echo "✅ Dry-run successful"
else
  echo "❌ Dry-run failed — aborting"
  exit 1
fi
echo

# 6. Run actual regeneration
echo "⚙️ Regenerating all initramfs images..."
dracut --regenerate-all --force -v

echo
echo "🎉 Done: All initramfs images regenerated successfully."
