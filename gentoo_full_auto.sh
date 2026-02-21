#!/bin/bash
set -e

# --- ПЕРЕМЕННЫЕ ---
DISK="/dev/sda"
PART_SWAP="${DISK}1"
PART_ROOT="${DISK}2"
# Ссылка на самый свежий Stage3 (OpenRC Desktop)
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc/stage3-amd64-desktop-openrc-20260215T164556Z.tar.xz"

echo ">>> 1. Подготовка диска..."
swapoff -a || true
# Создаем таблицу разделов (DOS), 4GB Swap, остальное Root
printf "o\nn\np\n1\n\n+4G\nt\n82\nn\np\n2\n\n\nw\n" | fdisk $DISK

mkswap $PART_SWAP
swapon $PART_SWAP
mkfs.ext4 -F $PART_ROOT
mount $PART_ROOT /mnt/gentoo

echo ">>> 2. Загрузка и распаковка системы..."
cd /mnt/gentoo
wget $STAGE3_URL
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
rm stage3-*.tar.xz

echo ">>> 3. Монтирование окружения..."
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

echo ">>> 4. Вход в CHROOT и автоматическая магия..."
cat <<EOF > /mnt/gentoo/final.sh
#!/bin/bash
source /etc/profile

# Настройка fstab
echo "$PART_ROOT / ext4 noatime 0 1" > /etc/fstab
echo "$PART_SWAP none swap sw 0 0" >> /etc/fstab

# Настройка Portage (чтобы не было варнов и запросов)
mkdir -p /etc/portage/package.accept_keywords
echo "sys-kernel/gentoo-kernel-bin ~amd64" > /etc/portage/package.accept_keywords/kernel
echo "ACCEPT_LICENSE=\"*\"" >> /etc/portage/make.conf
echo "MAKEOPTS=\"-j2\"" >> /etc/portage/make.conf

# Синхронизация
emerge-webrsync

# Автоматическое принятие всех изменений конфигов (etc-update)
CONFIG_PROTECT="-*" emerge --ask=n sys-kernel/gentoo-kernel-bin sys-boot/grub net-misc/dhcpcd

# Установка GRUB
grub-install $DISK
grub-mkconfig -o /boot/grub/grub.cfg

# Настройка сети и пароля
rc-update add dhcpcd default
echo "root:gentoo" | chpasswd

echo "--------------------------------------------------"
echo "ВСЁ! Система готова. Пароль: gentoo"
echo "Теперь пиши: exit, umount -R /mnt/gentoo, reboot"
echo "--------------------------------------------------"
EOF

chmod +x /mnt/gentoo/final.sh
chroot /mnt/gentoo /final.sh
