#!/bin/bash
set -e

DISK="/dev/sda"
PART_SWAP="${DISK}1"
PART_ROOT="${DISK}2"
# Your specific Stage3 link
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc/stage3-amd64-desktop-openrc-20260215T164556Z.tar.xz"

echo ">>> 1. Wiping disk..."
swapoff -a || true
# Create MBR, 4GB Swap, Root, and set Boot flag on sda2
printf "o\nn\np\n1\n\n+4G\nt\n82\nn\np\n2\n\n\na\n2\nw\n" | fdisk $DISK

echo ">>> 2. Formatting..."
mkswap $PART_SWAP
swapon $PART_SWAP
mkfs.ext4 -F $PART_ROOT
mount $PART_ROOT /mnt/gentoo

echo ">>> 3. Downloading your Stage3..."
cd /mnt/gentoo
wget "$STAGE3_URL" -O stage3.tar.xz

echo ">>> 4. Unpacking..."
tar xpvf stage3.tar.xz --xattrs-include='*.*' --numeric-owner
rm stage3.tar.xz

echo ">>> 5. Preparing chroot..."
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

echo ">>> 6. Inside CHROOT: Starting the engine..."
cat <<EOF > /mnt/gentoo/install_final.sh
#!/bin/bash
source /etc/profile

# Fixing repository config
mkdir -p /etc/portage/repos.conf
cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf

# Portage tuning
echo 'ACCEPT_LICENSE="*"' >> /etc/portage/make.conf
echo 'MAKEOPTS="-j2"' >> /etc/portage/make.conf
mkdir -p /etc/portage/package.accept_keywords
echo "sys-kernel/gentoo-kernel-bin ~amd64" > /etc/portage/package.accept_keywords/kernel

# Syncing repo
emerge-webrsync

# Setting profile explicitly to avoid 'invalid' errors
eselect profile set default/linux/amd64/23.0/desktop

# Installation (Kernel, Grub, Network)
CONFIG_PROTECT="-*" emerge --ask=n sys-boot/grub sys-kernel/gentoo-kernel-bin net-misc/dhcpcd

# Bootloader setup
grub-install --target=i386-pc $DISK
grub-mkconfig -o /boot/grub/grub.cfg

# System final touches
echo "$PART_ROOT / ext4 noatime 0 1" > /etc/fstab
echo "$PART_SWAP none swap sw 0 0" >> /etc/fstab
rc-update add dhcpcd default
echo "root:gentoo" | chpasswd

echo ">>> EVERYTHING FINISHED SUCCESSFULLY!"
EOF

chmod +x /mnt/gentoo/install_final.sh
chroot /mnt/gentoo /install_final.sh
