efibootmgr --create \
  --disk /dev/sda \
  --part 1 \
  --label "RHEL_sda_boot" \
  --loader '\EFI\RHEL\grubx64.efi'
