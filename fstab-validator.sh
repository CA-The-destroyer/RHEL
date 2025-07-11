#!/bin/bash
set -euo pipefail

echo "❓ Have you mounted the correct points (e.g., /mnt or chroot target)?"
read -p "Type 'yes' to continue: " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "🛑 Aborted. Please mount your target environment (e.g., /mnt) first."
  exit 1
fi

echo
echo "🔍 Validating /etc/fstab UUID entries..."
echo

FSTAB="/etc/fstab"
UUIDS_IN_SYSTEM=$(blkid | awk -F '"' '/UUID=/{print $2}')
FAIL=0

while IFS= read -r line; do
  # Skip comments and empty lines
  [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue

  # Extract UUID and mount point
  if [[ "$line" =~ UUID=([a-fA-F0-9\-]+) ]]; then
    uuid="${BASH_REMATCH[1]}"
    mountpoint=$(echo "$line" | awk '{print $2}')

    echo "🔸 Found UUID=$uuid → $mountpoint"

    # Check if UUID exists in system
    if echo "$UUIDS_IN_SYSTEM" | grep -q "$uuid"; then
      echo "   ✅ UUID exists in system"
    else
      echo "   ❌ UUID not found — check device or blkid output"
      ((FAIL++))
    fi

    # Check if mount point exists
    if [[ -d "$mountpoint" ]]; then
      echo "   ✅ Mount point exists"
    else
      echo "   ❌ Mount point $mountpoint is missing"
      ((FAIL++))
    fi

    # Is it mounted?
    if findmnt -n "$mountpoint" >/dev/null 2>&1; then
      echo "   ✅ Currently mounted"
    else
      echo "   ⚠️ Not mounted"
    fi

    echo
  fi
done < "$FSTAB"

echo "✅ Validation complete."
if (( FAIL > 0 )); then
  echo "❌ $FAIL issues found in /etc/fstab"
  exit 1
else
  echo "🎉 All UUIDs in fstab are valid and mount points exist."
  exit 0
fi
