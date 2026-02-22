#!/bin/bash
set -e

DISK="/dev/sda"
# Simple Stage3 (not desktop, just base)
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc/stage3-amd64-openrc-20260215T164556Z.tar.xz"

echo ">>> 1. Nuking the disk..."
swapoff -a || true
# IMPORTANT: 'a 2' makes the partition bootable for your 14yo BIOS
printf "o\nn\np\n1\n\n+4G\nt\n82\nn\np\n2\n\n\na\n2\nw\n" | fdisk $DISK

echo ">>> 2. Formatting..."
mkswap ${DISK}1 && swapon ${DISK}1
mkfs.ext4 -F ${DISK}2
mount ${DISK}2 /mnt/gentoo

echo ">>> 3. Downloading BASE Stage3..."
cd /mnt/gentoo
wget "$STAGE3_URL" -O s3.tar.xz
tar xpvf s3.tar.xz --xattrs-include='*.*' --numeric-owner

echo ">>> 4. Mounting..."
cp -L /etc/resolv.conf /mnt/gentoo/etc/
mount -t proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev

echo ">>> 5. Chrooting to finish this..."
cat <<EOF > /mnt/gentoo/final.sh
#!/bin/bash
source /etc/profile
emerge-webrsync

# Try to install GRUB. If it's already there, it just updates.
CONFIG_PROTECT="-*" emerge --ask=n sys-boot/grub sys-kernel/gentoo-kernel-bin net-misc/dhcpcd

# THE CRITICAL PART
grub-install --target=i386-pc $DISK
grub-mkconfig -o /boot/grub/grub.cfg

echo "${DISK}2 / ext4 noatime 0 1" > /etc/fstab
echo "${DISK}1 none swap sw 0 0" >> /etc/fstab
rc-update add dhcpcd default
echo "root:gentoo" | chpasswd
EOF

chmod +x /mnt/gentoo/final.sh
chroot /mnt/gentoo /final.sh
