umount -R /mnt || true

# Mount sda-based root volume again
mount /dev/mapper/rootvg_new-rootlv /mnt
mkdir -p /mnt/{boot,boot/efi,home,tmp,usr,var}

# Mount all other sda-based volumes
mount /dev/sda2 /mnt/boot
mount /dev/sda1 /mnt/boot/efi
mount /dev/mapper/rootvg_new-homelv /mnt/home
mount /dev/mapper/rootvg_new-tmplv /mnt/tmp
mount /dev/mapper/rootvg_new-usrlv /mnt/usr
mount /dev/mapper/rootvg_new-varlv /mnt/var

# Now bind system mounts from host to new root
for dir in dev proc sys run; do mount --bind /$dir /mnt/$dir; done

# ✅ You're now ready to chroot into the *sda-based* root:
chroot /mnt /bin/bash
