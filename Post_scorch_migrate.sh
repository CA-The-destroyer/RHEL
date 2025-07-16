#!/usr/bin/env bash
set -euxo pipefail

# Defaults & globals
DEVICE=/dev/sdc            # target disk (must match scorch-disk)
VG_NAME=rootvg_new         # LVM volume group
MOUNTPOINT=/mnt           # mountpoint for the new root
LOGFILE=/tmp/migrate.log  # migration log
DRY_RUN=0                 # pass --dry-run to skip destructive actions

# Helpers
run() { [[ $DRY_RUN -eq 1 ]] && echo "[DRY-RUN] $*" || "$@"; }
cleanup() {
  for d in dev proc sys run; do
    mountpoint -q "$MOUNTPOINT/$d" && umount -l "$MOUNTPOINT/$d" || true
  done
  mountpoint -q "$MOUNTPOINT" && umount -R "$MOUNTPOINT" || true
}
trap cleanup EXIT

# Option parsing
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=1; shift ;;  
    --device=*) DEVICE="${1#*=}"; shift ;;  
    --vg=*) VG_NAME="${1#*=}"; shift ;;  
    --mountpoint=*) MOUNTPOINT="${1#*=}"; shift ;;  
    *) echo "Unknown option: $1"; exit 1 ;;  
  esac
done

# Start logging
exec > >(tee -a "$LOGFILE") 2>&1
echo "🔧 Migration to $DEVICE starting; log: $LOGFILE"

# 1) Format partitions
run mkfs.fat -F32 "${DEVICE}1"
run mkfs.ext4   "${DEVICE}2"

# 2) LVM setup
run pvcreate --yes --force "${DEVICE}4"
run vgcreate "$VG_NAME" "${DEVICE}4"
run lvcreate -L2G   -n tmplv  "$VG_NAME"
run lvcreate -L15G  -n usrlv  "$VG_NAME"
run lvcreate -L20G  -n homelv "$VG_NAME"
run lvcreate -L10G  -n varlv  "$VG_NAME"
run lvcreate -l100%FREE -n rootlv "$VG_NAME"

# 3) Format LVs
for lv in tmplv usrlv homelv varlv rootlv; do
  run mkfs.ext4 "/dev/${VG_NAME}/${lv}"
done

# 4) Mount filesystems
run mkdir -p "$MOUNTPOINT"
run mount "/dev/${VG_NAME}/rootlv" "$MOUNTPOINT"
run mkdir -p "$MOUNTPOINT/boot" "$MOUNTPOINT/boot/efi"
run mount "${DEVICE}2" "$MOUNTPOINT/boot"
run mount "${DEVICE}1" "$MOUNTPOINT/boot/efi"
for dir in home tmp usr var; do
  run mkdir -p "$MOUNTPOINT/$dir"
  run mount "/dev/${VG_NAME}/${dir}lv" "$MOUNTPOINT/$dir"
done

# 5) /etc/fstab
EFI_UUID=$(blkid -s UUID -o value "${DEVICE}1")
BOOT_UUID=$(blkid -s UUID -o value "${DEVICE}2")
cat > "$MOUNTPOINT/etc/fstab" <<EOF
UUID=$EFI_UUID  /boot/efi  vfat defaults 0 2
UUID=$BOOT_UUID /boot      ext4 defaults 0 2
UUID=$(blkid -s UUID -o value "/dev/${VG_NAME}/rootlv") / ext4 defaults 0 1
UUID=$(blkid -s UUID -o value "/dev/${VG_NAME}/tmplv") /tmp ext4 defaults 0 2
UUID=$(blkid -s UUID -o value "/dev/${VG_NAME}/usrlv") /usr ext4 defaults 0 2
UUID=$(blkid -s UUID -o value "/dev/${VG_NAME}/homelv") /home ext4 defaults 0 2
UUID=$(blkid -s UUID -o value "/dev/${VG_NAME}/varlv") /var ext4 defaults 0 2
EOF

# 6) Rsync
run rsync -aAXHv --xattrs-include='security.selinux' --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} / "$MOUNTPOINT/"

# 7) Chroot & GRUB
for d in dev proc sys run; do run mount --bind "/$d" "$MOUNTPOINT/$d"; done
if [[ $DRY_RUN -eq 0 ]]; then
  chroot "$MOUNTPOINT" /usr/bin/env bash -euxo pipefail <<'EOF'
mount -a
grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=RHEL --recheck
grub2-install --target=i386-pc --boot-directory=/boot/grub2 --recheck $DEVICE
grub2-mkconfig -o /boot/efi/EFI/RHEL/grub.cfg
dracut --regenerate-all --force
restorecon -Rv /
EOF
fi

echo "✅ Migration complete. Logs: $LOGFILE"