#!/bin/bash
set -euo pipefail

echo "💥 WARNING: This will wipe all partitions on /dev/sda."
read -p "Type YES to proceed: " confirm
[[ "$confirm" != "YES" ]] && { echo "Aborted."; exit 1; }

echo "🔧 Partitioning /dev/sda..."
sgdisk -Z /dev/sda
sgdisk -n1:0:+200M -t1:ef00 -c1:"EFI System" \
       -n2:0:+10G  -t2:8300 -c2:"/boot" \
       -n3:0:0     -t3:8e00 -c3:"LVM" \
       /dev/sda

echo "🧹 Formatting partitions..."
mkfs.fat -F32 /dev/sda1
mkfs.ext4 /dev/sda2

echo "🧱 Creating new LVM volume group..."
pvcreate /dev/sda3
vgcreate rootvg_new /dev/sda3

echo "📦 Creating logical volumes..."
lvcreate -L 2G -n tmplv rootvg_new
lvcreate -L 15G -n usrlv rootvg_new
lvcreate -L 20G -n homelv rootvg_new
lvcreate -L 10G -n varlv rootvg_new
lvcreate -l 100%FREE -n rootlv rootvg_new

echo "🧷 Formatting logical volumes..."
mkfs.ext4 /dev/rootvg_new/tmplv
mkfs.ext4 /dev/rootvg_new/usrlv
mkfs.ext4 /dev/rootvg_new/homelv
mkfs.ext4 /dev/rootvg_new/varlv
mkfs.ext4 /dev/rootvg_new/rootlv

echo "📂 Mounting new root filesystem..."
mount /dev/rootvg_new/rootlv /mnt
mkdir -p /mnt/{boot,boot/efi,home,tmp,usr,var}
mount /dev/sda2 /mnt/boot
mkdir -p /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi
mount /dev/rootvg_new/homelv /mnt/home
mount /dev/rootvg_new/tmplv /mnt/tmp
mount /dev/rootvg_new/usrlv /mnt/usr
mount /dev/rootvg_new/varlv /mnt/var

echo "📋 Copying files from current system..."
rsync -aAXv / /mnt \
  --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"}

echo "🔗 Binding system directories..."
for dir in dev proc sys run; do mount --bind /$dir /mnt/$dir; done

echo "📥 Chrooting into new system..."
chroot /mnt /bin/bash << 'EOF'
set -euo pipefail
echo "📡 Installing GRUB to /dev/sda..."
grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=RHEL --recheck

echo "🛠 Regenerating GRUB config..."
grub2-mkconfig -o /boot/efi/EFI/RHEL/grub.cfg

echo "📦 Rebuilding initramfs..."
dracut --regenerate-all --force

echo "✅ Inside chroot complete."
exit
EOF

echo "🔽 Unmounting cleanly..."
for dir in run sys proc dev; do umount -lf /mnt/$dir; done
umount -R /mnt

echo "✅ Migration complete."
echo "👉 Please set /dev/sda as the first boot device in BIOS/UEFI, then reboot."
