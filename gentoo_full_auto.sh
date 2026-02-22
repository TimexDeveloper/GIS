#!/bin/bash
set -e

echo ">>> 1. Syncing partitions..."
partprobe /dev/sda || true
sleep 2

echo ">>> 2. Formatting..."
# Если тут пишет No such file, значит cfdisk не сохранил таблицу!
mkswap /dev/sda1
swapon /dev/sda1
mkfs.ext4 -F /dev/sda2
mount /dev/sda2 /mnt/gentoo
cd /mnt/gentoo

echo ">>> 3. Downloading Stage3..."
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc/stage3-amd64-desktop-openrc-20260215T164556Z.tar.xz
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

echo ">>> 4. Mounting environment..."
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

echo ">>> 5. Chroot install..."
cat <<EOF > /mnt/gentoo/inside.sh
#!/bin/bash
source /etc/profile

# Repository setup
mkdir -p /etc/portage/repos.conf
cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf

echo ">>> Syncing portage..."
emerge-webrsync

# Select Profile (Hardcode for 23.0 Desktop)
eselect profile set default/linux/amd64/23.0/desktop

echo ">>> Installing GRUB and Kernel (CRITICAL STEP)..."
# БЕЗ ЭТОГО ГРОБ НЕ НАЙДЕТСЯ!
CONFIG_PROTECT="-*" emerge --ask=n sys-boot/grub sys-kernel/gentoo-kernel-bin net-misc/dhcpcd

echo ">>> Configuring GRUB..."
grub-install --target=i386-pc /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

# Final configs
echo "/dev/sda2 / ext4 noatime 0 1" > /etc/fstab
echo "/dev/sda1 none swap sw 0 0" >> /etc/fstab
rc-update add dhcpcd default
echo "root:gentoo" | chpasswd

echo ">>> SUCCESS! EXIT AND REBOOT."
EOF

chmod +x /mnt/gentoo/inside.sh
chroot /mnt/gentoo /inside.sh
