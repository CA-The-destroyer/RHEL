#!/bin/bash
set -e

echo "💥 WARNING: This will overwrite all data on /dev/sda"
read -p "Type YES to proceed: " confirm
[[ "$confirm" != "YES" ]] && exit 1

# 1. Partition /dev/sda
sgdisk -Z /dev/sda
sgdisk -n1:0:+200M -t1:ef00 -c1:"EFI System" \
       -n2:0:+500M -t2:8300 -c2:"/boot" \
       -n3:0:0     -t3:8e00 -c3:"LVM" \
       /dev/sda

# 2. Format new filesystems
mkfs.fat -F32 /dev/sda1
mkfs.ext4 /dev/sda2

# 3. Setup new LVM VG as 'rootvg_new'
pvcreate /dev/sda3
vgcreate rootvg_new /dev/sda3

# Create logical volumes with same layout
lvcreate -L 2G -n tmplv rootvg_new
lvcreate -L 15G -n usrlv rootvg_new
lvcreate -L 20G -n homelv rootvg_new
lvcreate -L 10G -n varlv rootvg_new
lvcreate -l 100%FREE -n rootlv rootvg_new

# 4. Format the logical volumes
mkfs.ext4 /dev/rootvg_new/tmplv
mkfs.ext4 /dev/rootvg_new/usrlv
mkfs.ext4 /dev/rootvg_new/homelv
mkfs.ext4 /dev/rootvg_new/varlv
mkfs.ext4 /dev/rootvg_new/rootlv

# 5. Mount target system
mount /dev/rootvg_new/rootlv /mnt
mkdir -p /mnt/{boot,boot/efi,home,tmp,usr,var}
mount /dev/sda2 /mnt/boot
mount /dev/sda1 /mnt/boot/efi
mount /dev/rootvg_new/homelv /mnt/home
mount /dev/rootvg_new/tmplv /mnt/tmp
mount /dev/rootvg_new/usrlv /mnt/usr
mount /dev/rootvg_new/varlv /mnt/var

# 6. Copy from current root to new system
rsync -aAXv / /mnt \
  --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"}

# 7. Bind mount system directories and chroot
for dir in dev proc sys run; do mount --bind /$dir /mnt/$dir; done

chroot /mnt /bin/bash << 'EOF'
# Mount EFI if not already mounted
mount -a

# Install GRUB to sda
grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=RHEL --recheck
grub2-mkconfig -o /boot/efi/EFI/RHEL/grub.cfg

# Regenerate initramfs
dracut --regenerate-all --force

exit
EOF

# 8. Cleanup
for dir in run sys proc dev; do umount -lf /mnt/$dir; done
umount -R /mnt

echo "✅ Migration complete. Reboot and choose /dev/sda as the boot device in BIOS."
