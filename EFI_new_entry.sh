#!/bin/bash
set -euo pipefail

echo "🔧 Creating EFI boot entry for RHEL on /dev/sda1..."

efibootmgr --create \
  --disk /dev/sda \
  --part 1 \
  --label "RHEL_sda_boot" \
  --loader '\EFI\RHEL\grubx64.efi'

echo "✅ EFI boot entry created. Run 'efibootmgr' to confirm."
