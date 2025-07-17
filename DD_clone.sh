#!/usr/bin/env bash
# Post_DD_Clone.sh — Interactive DD clone & optional partition resize script

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

# 3️⃣ Prompt for DD clone parameters
read -rp "Enter source partition to clone (e.g. /dev/sda3): " SRC_PART
read -rp "Enter target partition to write to (e.g. /dev/sdc3): " TGT_PART

# 4️⃣ Validate partitions exist
for p in "${SRC_PART}" "${TGT_PART}"; do
  if [[ ! -b $p ]]; then
    echo "❌ Block device $p not found. Aborting."
    exit 1
  fi
done

# 5️⃣ Confirm & run dd
echo "🔨 About to clone ${SRC_PART} → ${TGT_PART}"
read -rp "Proceed with DD clone? [y/N]: " CONF
if [[ "$CONF" =~ ^[Yy] ]]; then
  dd if="${SRC_PART}" of="${TGT_PART}" bs=4M conv=noerror,sync status=progress
  echo "✅ DD clone complete."
else
  echo "⚠️  DD clone skipped."
  exit 1
fi

# 6️⃣ Show updated block layout
echo "Block devices after DD:"
lsblk
echo

# 7️⃣ Optional: partition resize on target disk
disk="${TGT_PART%[0-9]*}"
echo "Target disk deduced as ${disk}."
read -rp "Resize a partition on ${disk}? [y/N]: " RESIZE
if [[ "$RESIZE" =~ ^[Yy] ]]; then
  read -rp "Enter partition number to resize (e.g. 2): " PART_NUM
  read -rp "Enter new end for partition ${PART_NUM} (e.g. 100% or 320MiB): " NEW_END
  echo "➡️  Resizing ${disk} partition ${PART_NUM} to end at ${NEW_END}"
  parted "${disk}" --script resizepart "${PART_NUM}" "${NEW_END}"
  partprobe "${disk}"
  echo "✅ Partition ${PART_NUM} resized."
  echo
  echo "Block devices after resize:"
  lsblk
  echo
fi

# 8️⃣ Done
echo "🎉 DD and partition operations complete. You can now proceed to fstab update or boot operations."
