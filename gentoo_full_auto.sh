#!/bin/bash
set -e

DISK="/dev/sda"
PART_SWAP="${DISK}1"
PART_ROOT="${DISK}2"
# Stage3 link (the one you wanted)
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc/stage3-amd64-desktop-openrc-20260215T164556Z.tar.xz"
# Snapshot link to fix the "No such file" repo error
SNAP_URL="https://distfiles.gentoo.org/snapshots/gentoo-latest.tar.xz"

echo ">>> 1. Wiping and partitioning..."
swapoff -a || true
printf "o\nn\np\n1\n\n+4G\nt\n82\nn\np\n2\n\n\na\n2\nw\n" | fdisk $DISK

echo ">>> 2. Formatting..."
mkswap $PART_SWAP && swapon $PART_SWAP
mkfs.ext4 -F $PART_ROOT
mount $PART_ROOT /mnt/gentoo

echo ">>> 3. Downloading Stage3..."
cd /mnt/gentoo
wget "$STAGE3_URL" -O stage3.tar.xz
tar xpvf stage3.tar.xz --xattrs-include='*.*' --numeric-owner
rm stage3.tar.xz

echo ">>> 4. Manual Repo Setup (Fixing 'Invalid Location')..."
mkdir -p /mnt/gentoo/var/db/repos/gentoo
cd /mnt/gentoo/var/db/repos/gentoo
wget "$SNAP_URL" -O gentoo.tar.xz
echo ">>> Unpacking repo (Celeron is sweating...)"
tar xpvf gentoo.tar.xz --strip-components=1
rm gentoo.tar.xz

echo ">>> 5. Preparing environment..."
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

echo ">>> 6. Entering CHROOT for the final fight..."
cat <<EOF > /mnt/gentoo/ultimate_fix.sh
#!/bin/bash
source /etc/profile

# Force link profile (Hardcore mode)
ln -snf /var/db/repos/gentoo/profiles/default/linux/amd64/23.0/desktop /etc/portage/make.profile

# Portage config
mkdir -p /etc/portage/repos.conf
echo -e "[gentoo]\nlocation = /var/db/repos/gentoo" > /etc/portage/repos.conf/gentoo.conf
echo 'ACCEPT_LICENSE="*"' >> /etc/portage/make.conf
echo 'MAKEOPTS="-j2"' >> /etc/portage/make.conf
mkdir -p /etc/portage/package.accept_keywords
echo "sys-kernel/gentoo-kernel-bin ~amd64" > /etc/portage/package.accept_keywords/kernel

# Installing GRUB and Kernel with ONE J-THREASHOLD
echo ">>> Installing GRUB and Kernel (This is it...)"
CONFIG_PROTECT="-*" emerge --ask=n --oneshot sys-boot/grub sys-kernel/gentoo-kernel-bin net-misc/dhcpcd

# Bootloader
grub-install --target=i386-pc $DISK
grub-mkconfig -o /boot/grub/grub.cfg

# Final touches
echo "$PART_ROOT / ext4 noatime 0 1" > /etc/fstab
echo "$PART_SWAP none swap sw 0 0" >> /etc/fstab
rc-update add dhcpcd default
echo "root:gentoo" | chpasswd

echo ">>> HOLY SHIT, IT'S FINISHED!"
EOF

chmod +x /mnt/gentoo/ultimate_fix.sh
chroot /mnt/gentoo /ultimate_fix.sh
