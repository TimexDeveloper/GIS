#!/bin/bash
set -e

echo "--- 1. Preparation ---"
# Диск ты уже разметил через cfdisk, так что просто шьем файловые системы
mkswap /dev/sda1
swapon /dev/sda1
mkfs.ext4 -F /dev/sda2
mount /dev/sda2 /mnt/gentoo
cd /mnt/gentoo

echo "--- 2. Downloading Stage3 ---"
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc/stage3-amd64-desktop-openrc-20260215T164556Z.tar.xz
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

echo "--- 3. Mounting Environment ---"
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

echo "--- 4. Internal Install ---"
cat <<EOF > /mnt/gentoo/inside.sh
#!/bin/bash
source /etc/profile

# Sync and repair profile
emerge-webrsync
# Пытаемся поставить профиль (на 2026 год это скорее всего 23.0)
eselect profile set default/linux/amd64/23.0/desktop

# ВОТ ТУТ МЫ СТАВИМ ГРОБ, ЧТОБЫ ОН НЕ БЫЛ NOT FOUND
echo ">>> Installing GRUB and Kernel-bin..."
# CONFIG_PROTECT заставляет систему не тупить на конфигах
CONFIG_PROTECT="-*" emerge --ask=n sys-boot/grub sys-kernel/gentoo-kernel-bin net-misc/dhcpcd

# Настройка загрузчика
echo ">>> Running grub-install..."
grub-install --target=i386-pc /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

# Настройка сети и пароля
echo "/dev/sda2 / ext4 noatime 0 1" > /etc/fstab
echo "/dev/sda1 none swap sw 0 0" >> /etc/fstab
rc-update add dhcpcd default
echo "root:gentoo" | chpasswd

echo "DONE! Type exit, umount -R /mnt/gentoo and reboot."
EOF

chmod +x /mnt/gentoo/inside.sh
chroot /mnt/gentoo /inside.sh
