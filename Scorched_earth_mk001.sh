#!/usr/bin/env bash
set -euxo pipefail

# ─── Defaults & Global Variables ───────────────────────────────────────────────
LOGFILE=/tmp/migrate-sda.log
DRY_RUN=0
UEFI_ONLY=0
BIOS_ONLY=0
DEVICE=/dev/sda
VG_NAME=rootvg_new
MOUNTPOINT=/mnt

# ─── 1) Confirmation & Disk Wipe Prep ─────────────────────────────────────────
echo "💥 WARNING: This will wipe all partitions on ${DEVICE}."
read -rp "Type YES to proceed: " confirm
if [[ $confirm != YES ]]; then
  echo "Aborted."
  exit 1
fi

# ─── Redirect All Output to Log (and console) ─────────────────────────────────
exec > >(tee -a "$LOGFILE") 2>&1

echo "🔧 Starting migration to ${DEVICE} (logs: $LOGFILE)"

# ─── 1b) Unmount any mounted partitions on ${DEVICE} ───────────────────────────
echo "🔄 Unmounting existing partitions on ${DEVICE}..."
for part in $(lsblk -ln -o NAME,MOUNTPOINT | awk -v dev=$(basename "$DEVICE") '$1 ~ dev"[0-9]+" && $2!="" {print "/dev/"$1}'); do
  run umount -l "$part" || true
done

# ─── Helper: Dry-Run Wrapper ───────────────────────────────────────────────────
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[DRY-RUN] $*"
  else
    "$@"
  fi
}

# ─── Helper: Cleanup Function ─────────────────────────────────────────────────
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

# ─── Snapshot Original EFI BootOrder ───────────────────────────────────────────
if command -v efibootmgr &> /dev/null && [[ $BIOS_ONLY -eq 0 ]]; then
  ORIGINAL_ORDER=$(efibootmgr | grep '^BootOrder:' | awk '{print $2}') || ORIGINAL_ORDER=""
fi

# ─── Option Parsing ─────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)      DRY_RUN=1; shift ;;
    --uefi-only)    UEFI_ONLY=1; shift ;;
    --bios-only)    BIOS_ONLY=1; shift ;;
    --device=*)     DEVICE="${1#*=}"; shift ;;
    --vg=*)         VG_NAME="${1#*=}"; shift ;;
    --mountpoint=*) MOUNTPOINT="${1#*=}"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;  
  esac
done
[[ $UEFI_ONLY -eq 1 && $BIOS_ONLY -eq 1 ]] && { echo "❌ Cannot use both --uefi-only and --bios-only"; exit 1; }

# ─── 2) Wipe partitions & create new layout ────────────────────────────────────
echo "🔧 2) Wiping partitions & creating new GPT layout..."
run sgdisk --zap-all "$DEVICE"
run wipefs -a "$DEVICE"

run sgdisk \
  --new=1:0:+200M  --typecode=1:ef00 --change-name=1:"EFI System" \
  --new=2:0:+10G   --typecode=2:8300 --change-name=2:"boot" \
  --new=3:0:+1M    --typecode=3:ef02 --change-name=3:"BIOS Boot" \
  --new=4:0:0      --typecode=4:8e00 --change-name=4:"LVM" \
  "$DEVICE"

# ─── 3) Formatting partitions ──────────────────────────────────────────────────
echo "🧹 3) Formatting partitions..."
run mkfs.fat -F32 "${DEVICE}1"
run mkfs.ext4   "${DEVICE}2"

# ─── 4) LVM Setup ──────────────────────────────────────────────────────────────
echo "🧱 4) Setting up LVM on ${DEVICE}4..."
if vgdisplay "$VG_NAME" &> /dev/null; then
  echo "❌ VG $VG_NAME already exists"; exit 1
fi
run pvcreate --yes --force "${DEVICE}4"
run vgcreate "$VG_NAME" "${DEVICE}4"

# ─── 5) Logical Volume Creation ───────────────────────────────────────────────
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

# ─── 7) Mounting filesystems ──────────────────────────────────────────────────
echo "📂 7) Mounting filesystems under ${MOUNTPOINT}..."
run mkdir -p "$MOUNTPOINT"
run mount "/dev/${VG_NAME}/rootlv" "$MOUNTPOINT"
run mkdir -p "$MOUNTPOINT"/boot
run mount "${DEVICE}2" "$MOUNTPOINT/boot"
run mkdir -p "$MOUNTPOINT"/boot/efi
run mount "${DEVICE}1" "$MOUNTPOINT/boot/efi"
for dir in home tmp usr var; do
  run mkdir -p "$MOUNTPOINT/$dir"
  run mount "/dev/${VG_NAME}/${dir}lv" "$MOUNTPOINT/$dir"
done

# ─── 8) Generating /etc/fstab ─────────────────────────────────────────────────
echo "📋 8) Generating /etc/fstab..."
EFI_UUID=$(blkid -s UUID -o value "${DEVICE}1")
BOOT_UUID=$(blkid -s UUID -o value "${DEVICE}2")
declare -A LV_UUID
for lv in rootlv tmplv usrlv homelv varlv; do
  LV_UUID["$lv"]=$(blkid -s UUID -o value "/dev/${VG_NAME}/${lv}")
done
cat > "${MOUNTPOINT}/etc/fstab" <<EOF
# fs       mount   type   opts   dump pass
UUID=${EFI_UUID}    /boot/efi   vfat  defaults 0 2
UUID=${BOOT_UUID}   /boot       ext4  defaults 0 2
UUID=${LV_UUID[rootlv]} /      ext4  defaults 0 1
UUID=${LV_UUID[tmplv]}  /tmp   ext4  defaults 0 2
UUID=${LV_UUID[usrlv]}  /usr   ext4  defaults 0 2
UUID=${LV_UUID[homelv]} /home ext4  defaults 0 2
UUID=${LV_UUID[varlv]}  /var   ext4  defaults 0 2
EOF

# ─── 9) Rsync live system ─────────────────────────────────────────────────────
echo "📋 9) Rsyncing live system..."
run rsync -aAXHv --xattrs-include='security.selinux' \
  --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
  / "$MOUNTPOINT/"

# ─── 10) Bind & chroot for bootloader and initramfs ───────────────────────────
echo "🔗 10) Binding virtual filesystems..."
for d in dev proc sys run; do
  run mount --bind "/$d" "$MOUNTPOINT/$d"
done

if [[ $DRY_RUN -eq 1 ]]; then
  echo "[DRY-RUN] Skipping chroot steps."
else
  chroot "$MOUNTPOINT" /usr/bin/env bash -euxo pipefail <<EOF
mount -a
[[ \$BIOS_ONLY -eq 0 ]] && grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=RHEL --recheck --debug
[[ \$UEFI_ONLY -eq 0 ]] && grub2-install --target=i386-pc --boot-directory=/boot/grub2 --recheck /dev/sda
grub2-mkconfig -o /boot/efi/EFI/RHEL/grub.cfg
dracut --regenerate-all --force
restorecon -Rv /
EOF
fi

# ─── 11) Update EFI boot order ─────────────────────────────────────────────────
echo "🔧 11) Updating EFI boot order..."
if [[ $BIOS_ONLY -eq 0 && $DRY_RUN -eq 0 && -n $ORIGINAL_ORDER ]]; then
  NEW=$(efibootmgr | grep -i 'RHEL' | head -n1 | sed -E 's/Boot([0-9A-F]+).*/\1/')
  efibootmgr -o ${NEW},${ORIGINAL_ORDER}
fi

# ─── 12) Cleanup & finish ─────────────────────────────────────────────────────
echo "🔽 12) Cleanup and finish..."
cleanup
echo -e "\n✅ Migration complete. Logs: $LOGFILE"
