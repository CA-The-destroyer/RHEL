#!/bin/bash
set -e

echo "💥 WARNING: This will overwrite data on /dev/sda"
read -p "Type YES to proceed: " confirm
[[ "$confirm" != "YES" ]] && exit 1

# 1. Partition sda to match sdb layout
sgdisk -Z /dev/sda  # Zap old partitions
sgdisk -n1:0:+200M -t1:ef00 -c1:"EFI System" \
       -n2:0:+500M -t2:8300 -c2:"/boot" \
       -n3:0:0     -t3:8e00 -c3:"LVM" \
       /dev/sda

# 2. Format EFI and /boot partitions
mkfs.fat -F32 /dev/sda1
mkfs.ext4 /dev/sda2

# 3. Setup LVM on sda3
pvcreate /dev/sda3
vgcreate rootvg /dev/sda3
lvcreate -L 2G   -n tmplv rootvg
lvcreate -L 15G  -n usrlv rootvg
lvcreate -L 20G  -n homelv rootvg
lvcreate -L 10G  -n varlv rootvg
lvcreate -l 100%FREE -n rootlv rootvg

mkfs.ext4 /dev/rootvg/tmplv
mkfs.ext4 /dev/rootvg/usrlv
mkfs.ext4 /dev/rootvg/homelv
mkfs.ext4 /dev/rootvg/varlv
mkfs.ext4 /dev/rootvg/rootlv

# 4. Mount target system
mount /dev/rootvg/rootlv /mnt
mkdir -p /mnt/{boot,boot/efi,home,tmp,usr,var}
mount /dev/sda2 /mnt/boot
mount /dev/sda1 /mnt/boot/efi
mount /dev/rootvg/homelv /mnt/home
mount /dev/rootvg/tmplv /mnt/tmp
mount /dev/rootvg/usrlv /mnt/usr
mount /dev/rootvg/varlv /mnt/var

# 5. Copy everything from current system (sdb) to /mnt
rsync -aAXv / --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} /mnt

# 6. Bind mount and chroot
for dir in dev proc sys run; do mount --bind /$dir /mnt/$dir; done
chroot /mnt /bin/bash << 'EOF'
grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=RHEL --recheck
grub2-mkconfig -o /boot/efi/EFI/RHEL/grub.cfg
dracut --regenerate-all --force
exit
EOF

# 7. Unmount everything
for dir in run sys proc dev; do umount -lf /mnt/$dir; done
umount -R /mnt

echo "✅ Migration complete. Set BIOS to boot from sda and reboot."
