#!/bin/bash
# Настройка переменных — ПРОВЕРЬ ИХ!
DISK="/dev/sda"
PART_SWAP="${DISK}1"
PART_ROOT="${DISK}2"

set -e

echo "--- 1. Подготовка дисков ---"
swapoff -a || true
mkswap -f "$PART_SWAP"
swapon "$PART_SWAP"
mkfs.ext4 -F "$PART_ROOT"
mount "$PART_ROOT" /mnt/gentoo

echo "--- 2. Загрузка Stage3 ---"
cd /mnt/gentoo
# Прямая ссылка на актуальный билд
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc/stage3-amd64-desktop-openrc-20260215T164556Z.tar.xz
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
rm stage3-*.tar.xz

echo "--- 3. Монтирование окружения ---"
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

echo "--- 4. Вход в CHROOT и настройка ---"
cat <<EOF > /mnt/gentoo/install.sh
#!/bin/bash
source /etc/profile

# Быстрая синхронизация
emerge-webrsync

# Настройка fstab через UUID (это надежнее)
ROOT_UUID=\$(blkid -s UUID -o value $PART_ROOT)
SWAP_UUID=\$(blkid -s UUID -o value $PART_SWAP)
echo "UUID=\$ROOT_UUID / ext4 noatime 0 1" > /etc/fstab
echo "UUID=\$SWAP_UUID none swap sw 0 0" >> /etc/fstab

# Настройка make.conf (минимализм для старого ноута)
cat <<CONF > /etc/portage/make.conf
COMMON_FLAGS="-O2 -march=native -pipe"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
MAKEOPTS="-j2"
ACCEPT_LICENSE="*"
USE="X elogind -systemd -gnome -kde"
VIDEO_CARDS="intel"
CONF

# Установка ядра (бинарного) и GRUB
# Ограничиваем аппетиты портажа, чтобы не вылетало
emerge --ask=n sys-kernel/gentoo-kernel-bin
emerge --ask=n sys-boot/grub

# Настройка GRUB
grub-install $DISK
grub-mkconfig -o /boot/grub/grub.cfg

# Настройка сети (DHCP по умолчанию для Ethernet)
emerge --ask=n net-misc/dhcpcd
rc-update add dhcpcd default

# Пароль
echo "root:gentoo" | chpasswd

echo "УСТАНОВКА ЗАВЕРШЕНА!"
EOF

chmod +x /mnt/gentoo/install.sh
chroot /mnt/gentoo /install.sh
