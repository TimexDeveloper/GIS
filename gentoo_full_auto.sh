#!/bin/bash
set -e

DISK="/dev/sda"
PART_SWAP="${DISK}1"
PART_ROOT="${DISK}2"
# Latest Stage3 URL
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/20250216T163402Z/stage3-amd64-desktop-openrc-20250216T163402Z.tar.xz"

echo ">>> 1. Cleaning disk..."
swapoff -a || true
printf "o\nn\np\n1\n\n+4G\nt\n82\nn\np\n2\n\n\na\n2\nw\n" | fdisk $DISK

echo ">>> 2. Formatting..."
mkswap $PART_SWAP
swapon $PART_SWAP
mkfs.ext4 -F $PART_ROOT
mount $PART_ROOT /mnt/gentoo

echo ">>> 3. Downloading Stage3..."
cd /mnt/gentoo
wget $STAGE3_URL -O stage3.tar.xz
tar xpvf stage3.tar.xz --xattrs-include='*.*' --numeric-owner
rm stage3.tar.xz

echo ">>> 4. Mounting environment..."
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

echo ">>> 5. Entering CHROOT and fixing profile..."
cat <<EOF > /mnt/gentoo/fix.sh
#!/bin/bash
source /etc/profile

# Force create repos.conf directory
mkdir -p /etc/portage/repos.conf
cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf

# Set Portage Config
echo 'ACCEPT_LICENSE="*"' >> /etc/portage/make.conf
echo 'MAKEOPTS="-j2"' >> /etc/portage/make.conf
mkdir -p /etc/portage/package.accept_keywords
echo "sys-kernel/gentoo-kernel-bin ~amd64" > /etc/portage/package.accept_keywords/kernel

# Syncing
echo ">>> Syncing..."
emerge-webrsync

# Select profile (to avoid 'invalid profile' error)
# We pick the basic desktop profile
eselect profile set default/linux/amd64/23.0/desktop

# Installing GRUB and Kernel
echo ">>> Installing GRUB and Kernel (STAY CALM, CELERON IS WORKING)..."
CONFIG_PROTECT="-*" emerge --ask=n sys-boot/grub sys-kernel/gentoo-kernel-bin net-misc/dhcpcd

# Finalizing GRUB
grub-install --target=i386-pc $DISK
grub-mkconfig -o /boot/grub/grub.cfg

# Network and Pass
echo "$PART_ROOT / ext4 noatime 0 1" > /etc/fstab
echo "$PART_SWAP none swap sw 0 0" >> /etc/fstab
rc-update add dhcpcd default
echo "root:gentoo" | chpasswd

echo ">>> SUCCESS! Type exit, umount -R /mnt/gentoo, reboot."
EOF

chmod +x /mnt/gentoo/fix.sh
chroot /mnt/gentoo /fix.sh
