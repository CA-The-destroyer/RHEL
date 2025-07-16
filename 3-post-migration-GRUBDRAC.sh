#!/usr/bin/env bash
set -euxo pipefail

# Defaults
DEVICE=/dev/sdc           # target disk (partition numbers must match)
MOUNTPOINT=/mnt           # root mountpoint

# Usage: post-migration-fix.sh [--device=/dev/sdX] [--mountpoint=/path]
for arg in "$@"; do
  case $arg in
    --device=*)    DEVICE="${arg#*=}"; shift ;;  
    --mountpoint=*) MOUNTPOINT="${arg#*=}"; shift ;;  
    *) echo "Unknown option: $arg"; exit 1 ;;  
  esac
done

# Ensure mountpoint exists
mkdir -p "$MOUNTPOINT"

# 1) Mount /boot and EFI
mount "${DEVICE}2" "$MOUNTPOINT/boot"
mount "${DEVICE}1" "$MOUNTPOINT/boot/efi"

# 2) Bind-mount kernel namespaces
for d in dev proc sys run; do
  mount --bind "/$d" "$MOUNTPOINT/$d"
done

# 3) Chroot to install GRUB and rebuild initramfs
chroot "$MOUNTPOINT" /usr/bin/env bash -euxo pipefail <<EOF
# UEFI install (optional --removable)
grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=RHEL --recheck --removable
# BIOS fallback
grub2-install --target=i386-pc --boot-directory=/boot/grub2 --recheck $DEVICE
# Regenerate configuration
grub2-mkconfig -o /boot/efi/EFI/RHEL/grub.cfg
# Rebuild initramfs
dracut --force
EOF

# 4) Cleanup mounts
umount -l "$MOUNTPOINT/dev" "$MOUNTPOINT/proc" "$MOUNTPOINT/sys" "$MOUNTPOINT/run"
umount -R "$MOUNTPOINT"

echo "✅ Post-migration fix complete."