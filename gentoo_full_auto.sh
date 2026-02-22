#!/bin/bash
set -e

DISK="/dev/sda"
PART_SWAP="${DISK}1"
PART_ROOT="${DISK}2"

echo ">>> 1. Wiping disk..."
swapoff -a || true
printf "o\nn\np\n1\n\n+4G\nt\n82\nn\np\n2\n\n\na\n2\nw\n" | fdisk $DISK

echo ">>> 2. Formatting..."
mkswap $PART_SWAP
swapon $PART_SWAP
mkfs.ext4 -F $PART_ROOT
mount $PART_ROOT /mnt/gentoo

echo ">>> 3. Downloading LATEST Stage3 (Auto-detect)..."
cd /mnt/gentoo
# ЭТА МАГИЯ НАХОДИТ ПОСЛЕДНЮЮ ССЫЛКУ САМА
STAGE3_PATH=$(wget -qO- https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc/ | grep -oP 'stage3-amd64-desktop-openrc-\d{8}T\d{6}Z\.tar\.xz' | head -n 1)
wget "https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc/$STAGE3_PATH" -O stage3.tar.xz

echo ">>> 4. Unpacking..."
tar xpvf stage3.tar.xz --xattrs-include='*.*' --numeric-owner
rm stage3.tar.xz

echo ">>> 5. Mounting environment..."
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

echo ">>> 6. Entering CHROOT and fixing EVERYTHING..."
cat <<EOF > /mnt/gentoo/fix.sh
#!/bin/bash
source /etc/profile

# Fixing repository locations
mkdir -p /etc/portage/repos.conf
cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf

# Portage Config
echo 'ACCEPT_LICENSE="*"' >> /etc/portage/make.conf
echo 'MAKEOPTS="-j2"' >> /etc/portage/make.conf
mkdir -p /etc/portage/package.accept_keywords
echo "sys-kernel/gentoo-kernel-bin ~amd64" > /etc/portage/package.accept_keywords/kernel

# Syncing (This is mandatory)
emerge-webrsync

# Profile Fix (Automatic pick for 23.0 desktop)
eselect profile set default/linux/amd64/23.0/desktop

# Core installation
CONFIG_PROTECT="-*" emerge --ask=n sys-boot/grub sys-kernel/gentoo-kernel-bin net-misc/dhcpcd

# Bootloader
grub-install --target=i386-pc $DISK
grub-mkconfig -o /boot/grub/grub.cfg

# Network, Fstab & Password
echo "$PART_ROOT / ext4 noatime 0 1" > /etc/fstab
echo "$PART_SWAP none swap sw 0 0" >> /etc/fstab
rc-update add dhcpcd default
echo "root:gentoo" | chpasswd

echo ">>> DONE! Reboot and enjoy your Celeron-beast."
EOF

chmod +x /mnt/gentoo/fix.sh
chroot /mnt/gentoo /fix.sh
