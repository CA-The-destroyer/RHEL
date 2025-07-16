#!/usr/bin/env bash
set -euo pipefail

# ─── Logging & Cleanup ─────────────────────────────────────────────────────────
LOGFILE=/tmp/migrate-sda.log
exec &> "$LOGFILE"
cleanup() {
  echo "🧹 Cleaning up mounts..."
  for d in run sys proc dev; do
    if mountpoint -q "${MOUNTPOINT}/$d"; then
      umount -l "${MOUNTPOINT}/$d" || true
    fi
  done
  if mountpoint -q "$MOUNTPOINT"; then
    umount -R "$MOUNTPOINT" || true
  fi
}
trap cleanup EXIT

# ─── Defaults & Option Parsing ────────────────────────────────────────────────
DRY_RUN=0
UEFI_ONLY=0
BIOS_ONLY=0
DEVICE=/dev/sda
VG_NAME=rootvg_new
MOUNTPOINT=/mnt

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)       DRY_RUN=1; shift ;;
    --uefi-only)     UEFI_ONLY=1; shift ;;
    --bios-only)     BIOS_ONLY=1; shift ;;
    --device=*)      DEVICE="${1#*=}"; shift ;;
    --vg=*)          VG_NAME="${1#*=}"; shift ;;
    --mountpoint=*)  MOUNTPOINT="${1#*=}"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done
[[ $UEFI_ONLY -eq 1 && $BIOS_ONLY -eq 1 ]] && { echo "❌ Cannot use both --uefi-only and --bios-only"; exit 1; }

# Wrapper to support dry-run
run() { 
  if [[ $DRY_RUN -eq 1 ]]; then 
    echo "[DRY-RUN] $*" 
  else 
    "$@" 
  fi
}

# Snapshot original EFI BootOrder (for later reordering)
if [[ $BIOS_ONLY -eq 0 ]]; then
  ORIGINAL_ORDER=$(efibootmgr | grep '^BootOrder:' | awk '{print $2}') || ORIGINAL_ORDER=""
fi

# ─── 1) Confirmation & Wipe ───────────────────────────────────────────────────
echo "💥 WARNING: This will wipe all partitions on ${DEVICE}."
read -rp "Type YES to proceed: " confirm
[[ $confirm != YES ]] && { echo "Aborted."; exit 1; }

echo "🔧 1) Wiping existing partitions on ${DEVICE}..."
run sgdisk --zap-all "$DEVICE"
run wipefs -a "$DEVICE"

# ─── 2) Partitioning ───────────────────────────────────────────────────────────
echo "🔧 2) Creating EFI, BIOS-Boot, /boot & LVM partitions..."
run sgdisk \
  --new=1:0:+200M  --typecode=1:ef00 --change-name=1:"EFI System" \
  --new=2:0:+1M     --typecode=2:ef02 --change-name=2:"BIOS Boot" \
  --new=3:0:+10G    --typecode=3:8300 --change-name=3:"boot" \
  --new=4:0:0       --typecode=4:8e00 --change-name=4:"LVM" \
  "$DEVICE"

# ─── 3) Formatting ─────────────────────────────────────────────────────────────
echo "🧹 3) Formatting partitions..."
run mkfs.fat -F32 "${DEVICE}1"
run mkfs.ext4 "${DEVICE}3"

# ─── 4) LVM Setup ─────────────────────────────────────────────────────────────
echo "🧱 4) Setting up LVM on ${DEVICE}4..."
if vgdisplay "$VG_NAME" &> /dev/null; then
  echo "❌ Volume group $VG_NAME already exists. Remove it or choose another VG_NAME."; exit 1
fi
run pvcreate --yes --force "${DEVICE}4"
run vgcreate "$VG_NAME" "${DEVICE}4"

# ─── 5) LV Creation ────────────────────────────────────────────────────────────
echo "📦 5) Creating logical volumes..."
for spec in tmplv:2G usrlv:15G homelv:20G varlv:10G rootlv:100%FREE; do
  IFS=':' read -r lv sz <<< "$spec"
  if [[ $lv == rootlv ]]; then
    run lvcreate -l "$sz" -n "$lv" "$VG_NAME"
  else
    run lvcreate -L "$sz" -n "$lv" "$VG_NAME"
  fi
done

# ─── 6) Formatting LVs ─────────────────────────────────────────────────────────
echo "🧷 6) Formatting logical volumes..."
for lv in tmplv usrlv homelv varlv rootlv; do
  run mkfs.ext4 "/dev/${VG_NAME}/${lv}"
done

# ─── 7) Mounting ───────────────────────────────────────────────────────────────
echo "📂 7) Mounting target filesystem under ${MOUNTPOINT}..."
[[ $DRY_RUN -eq 0 ]] && run mount "/dev/${VG_NAME}/rootlv" "$MOUNTPOINT"
run mkdir -p "$MOUNTPOINT"/boot
[[ $DRY_RUN -eq 0 ]] && run mount "${DEVICE}3" "$MOUNTPOINT/boot"
run mkdir -p "$MOUNTPOINT"/boot/efi
[[ $DRY_RUN -eq 0 ]] && run mount "${DEVICE}1" "$MOUNTPOINT/boot/efi"

for dir in home tmp usr var; do
  run mkdir -p "$MOUNTPOINT/$dir"
  [[ $DRY_RUN -eq 0 ]] && run mount "/dev/${VG_NAME}/${dir}lv" "$MOUNTPOINT/$dir"
done

# ─── 8) /etc/fstab Generation ─────────────────────────────────────────────────
echo "📋 8) Generating /etc/fstab on new root..."
EFI_UUID=$(blkid -s UUID -o value "${DEVICE}1")  || { echo "❌ Can't read UUID of ${DEVICE}1"; exit 1; }
BOOT_UUID=$(blkid -s UUID -o value "${DEVICE}3") || { echo "❌ Can't read UUID of ${DEVICE}3"; exit 1; }
declare -A LV_UUID
for lv in rootlv tmplv usrlv homelv varlv; do
  u=$(blkid -s UUID -o value "/dev/${VG_NAME}/${lv}") || { echo "❌ Can't read UUID of /dev/${VG_NAME}/${lv}"; exit 1; }
  LV_UUID["$lv"]=$u
done

run bash -c "cat > ${MOUNTPOINT}/etc/fstab <<EOF
# <fs>                          <mount point>  <type>  <options>         <dump> <pass>
UUID=${EFI_UUID}                /boot/efi      vfat    defaults          0      2
UUID=${BOOT_UUID}               /boot          ext4    defaults          0      2
UUID=${LV_UUID[rootlv]}         /              ext4    defaults          0      1
UUID=${LV_UUID[tmplv]}          /tmp           ext4    defaults          0      2
UUID=${LV_UUID[usrlv]}          /usr           ext4    defaults          0      2
UUID=${LV_UUID[homelv]}         /home          ext4    defaults          0      2
UUID=${LV_UUID[varlv]}          /var           ext4    defaults          0      2
EOF"

# ─── 9) Rsync ──────────────────────────────────────────────────────────────────
echo "📋 9) Rsyncing live system into new root..."
run rsync -aAXHv \
  --xattrs-include='security.selinux' \
  --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
  / "$MOUNTPOINT/"

# ─── 10) Bind & Chroot ─────────────────────────────────────────────────────────
echo "🔗 10) Binding virtual filesystems..."
for d in dev proc sys run; do
  run mount --bind "/$d" "$MOUNTPOINT/$d"
done

echo "📥 11) Chroot & configure GRUB + initramfs..."
if [[ $DRY_RUN -eq 1 ]]; then
  echo "[DRY-RUN] Skipping chroot configuration."
else
  chroot "$MOUNTPOINT" /usr/bin/env bash -eux <<EOF
mount -a
[[ \$BIOS_ONLY -eq 0 ]] && grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=RHEL --recheck --debug
[[ \$UEFI_ONLY -eq 0 ]] && grub2-install --target=i386-pc --boot-directory=/boot/grub2 --recheck /dev/sda
grub2-mkconfig -o /boot/efi/EFI/RHEL/grub.cfg
dracut --regenerate-all --force
restorecon -Rv /
EOF
fi

# ─── 12) EFI BootOrder Reorder ─────────────────────────────────────────────────
echo "🔧 12) Updating EFI BootOrder (if UEFI)..."
if [[ $BIOS_ONLY -eq 0 && $DRY_RUN -eq 0 ]]; then
  NEW_BOOTNUM=$(efibootmgr | grep -i 'RHEL' | head -n1 | sed -E 's/Boot([0-9A-Fa-f]+).*/\1/')
  [[ -n $NEW_BOOTNUM && -n $ORIGINAL_ORDER ]] && efibootmgr -o ${NEW_BOOTNUM},${ORIGINAL_ORDER}
fi

# ─── 13) Unmount & Finish ──────────────────────────────────────────────────────
echo "🔽 13) Unmounting everything..."
cleanup

echo "✅ Migration + GRUB setup complete."
echo "
👉 After reboot, verify:
   mountpoint -q /            && echo '/ OK'
   mountpoint -q /boot        && echo '/boot OK'
   lsblk -f | grep ${VG_NAME} && echo 'LVM OK'
   uname -r                   && echo 'Kernel OK'

🔍 Full log: $LOGFILE
"
