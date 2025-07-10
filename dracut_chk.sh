#!/bin/bash
set -euo pipefail

echo "🔍 Checking environment for dracut..."

echo
echo "📁 Kernel module directories under /lib/modules:"
ls -1 /lib/modules || echo "❌ No kernel modules found!"

echo
echo "📁 Kernel files in /boot:"
ls -lh /boot/vmlinuz-* || echo "❌ No vmlinuz kernel files!"
ls -lh /boot/initramfs-* || echo "⚠️ No initramfs images (yet)"

echo
echo "📂 EFI bootloaders (if /boot/efi is present):"
if [[ -d /boot/efi/EFI ]]; then
  find /boot/efi/EFI -name '*.efi'
else
  echo "⚠️ /boot/efi/EFI not found"
fi

echo
echo "🔗 Verifying required mount points..."
for d in /proc /sys /dev /run; do
  mountpoint -q $d && echo "✅ $d is mounted" || echo "❌ $d is not mounted"
done

echo
echo "📦 Checking for dracut executable and version..."
command -v dracut && dracut --version || echo "❌ dracut not found!"

echo
echo "🧪 Running dry-run dracut on latest kernel..."
latest_kernel=$(basename /lib/modules/* | sort -V | tail -n1)
echo "→ Kernel version: $latest_kernel"

dracut --verbose --force --dry-run /tmp/initramfs-dryrun.img "$latest_kernel" || {
  echo "❌ Dry-run failed — dracut is broken or kernel not present"
}

echo
echo "✅ If no errors above, you can now run:"
echo "    dracut --regenerate-all --force -v"
