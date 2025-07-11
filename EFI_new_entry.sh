efibootmgr --create \
  --disk /dev/sda \
  --part 1 \
  --label "RHEL_new Boot" \
  --loader '\EFI\RHEL_new\grubx64.efi'
