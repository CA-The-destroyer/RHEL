#!/usr/bin/env bash
set -euo pipefail

# Show current block devices
echo "Available block devices:"
lsblk
echo

# Prompt for source and target
read -rp "Enter source device (if), e.g. /dev/sda3: " SRC
if [[ ! -b "$SRC" ]]; then
  echo >&2 "Error: '$SRC' is not a valid block device."
  exit 1
fi

read -rp "Enter target device (of), e.g. /dev/sdc3: " DST
if [[ ! -b "$DST" ]]; then
  echo >&2 "Error: '$DST' is not a valid block device."
  exit 1
fi

# Confirm
echo
read -rp "About to clone '$SRC' → '$DST'. Proceed? (y/N): " CONF
if [[ ! "$CONF" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

# Run dd
echo
echo "Running: dd if=$SRC of=$DST bs=1M conv=noerror,sync status=progress"
sudo dd if="$SRC" of="$DST" bs=1M conv=noerror,sync status=progress

echo
echo "Clone complete."
echo "Run Post_DD_Fstab_validation.sh" 


