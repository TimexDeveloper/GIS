#!/bin/bash
set -e

DISK="/dev/sda"
PART_SWAP="${DISK}1"
PART_ROOT="${DISK}2"
# Stage3 URL - make sure you have internet!
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc/stage3-amd64-desktop-openrc-20260215T164556Z.tar.xz"

echo ">>> 1. Wiping disk and creating partitions..."
swapoff -a || true
# Wipe partition table and create new MBR (DOS)
# 4GB Swap, rest for Root, Set Root partition as Bootable (*)
printf "o\nn\np\n1\n\n+4G\nt\n82\nn\np\n2\n\n\na\n2\nw\n" | fdisk $DISK

echo ">>> 2. Formatting partitions..."
mkswap $PART_SWAP
swapon $PART_SWAP
mkfs.ext4 -F $PART_ROOT
mount $PART_ROOT /mnt/gentoo

echo ">>> 3. Downloading and unpacking Stage3..."
cd /mnt/gentoo
wget $STAGE3_URL
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
rm stage3-*.tar.xz
sync

echo ">>> 4. Mounting system directories..."
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

echo ">>> 5. Entering CHROOT for installation..."
cat <<EOF > /mnt/gentoo/finalize.sh
#!/bin/bash
source /etc/profile

# Portage Config for Celeron
echo 'ACCEPT_LICENSE="*"' >> /etc/portage/make.conf
echo 'MAKEOPTS="-j2"' >> /etc/portage/make.conf
echo 'PORTAGE_NICENESS=19' >> /etc/portage/make.conf
mkdir -p /etc/portage/package.accept_keywords
echo "sys-kernel/gentoo-kernel-bin ~amd64" > /etc/portage/package.accept_keywords/kernel

# Fstab setup
echo "$PART_ROOT / ext4 noatime 0 1" > /etc/fstab
echo "$PART_SWAP none swap sw 0 0" >> /etc/fstab

# Sync and install Kernel + GRUB
echo ">>> Syncing portage (emerge-webrsync)..."
emerge-webrsync
echo ">>> Installing kernel and bootloader (this will take a LONG time)..."
CONFIG_PROTECT="-*" emerge --ask=n sys-kernel/gentoo-kernel-bin sys-boot/grub net-misc/dhcpcd

# Final Bootloader configuration
echo ">>> Installing GRUB to MBR..."
grub-install --target=i386-pc $DISK
grub-mkconfig -o /boot/grub/grub.cfg

# Network and root password
rc-update add dhcpcd default
echo "root:gentoo" | chpasswd

echo ">>> FINISHED! System is ready."
echo ">>> Password is: gentoo"
echo ">>> Type: exit, then umount -R /mnt/gentoo, then reboot."
EOF

chmod +x /mnt/gentoo/finalize.sh
chroot /mnt/gentoo /finalize.sh
