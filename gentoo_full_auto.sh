#!/bin/bash
set -e

echo "--- 1. Подготовка дисков (/dev/sda1-swap, /dev/sda2-root) ---"
mkswap /dev/sda1
swapon /dev/sda1
mkfs.ext4 -F /dev/sda2
mount /dev/sda2 /mnt/gentoo
cd /mnt/gentoo

echo "--- 2. Загрузка и распаковка Stage3 ---"
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc/stage3-amd64-desktop-openrc-20260215T164556Z.tar.xz
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

echo "--- 3. Настройка окружения ---"
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

echo "--- 4. Работа внутри CHROOT ---"
cat <<'EOF' > /mnt/gentoo/final_step.sh
#!/bin/bash
source /etc/profile
export PS1="(chroot) $PS1"

# Синхронизация (быстрый вариант)
emerge-webrsync

# Настройка fstab (чтобы система знала, где корень и своп)
cat <<FSTAB > /etc/fstab
/dev/sda1  none  swap  sw  0 0
/dev/sda2  /     ext4  noatime  0 1
FSTAB

# Установка бинарного ядра и загрузчика
# Это сэкономит тебе ДЕНЬ компиляции
echo "sys-kernel/gentoo-kernel-bin" >> /etc/portage/package.accept_keywords
emerge --ask=n sys-kernel/gentoo-kernel-bin
emerge --ask=n sys-boot/grub

# Установка GRUB на диск
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

# Пароль рута (сделаем 'gentoo' по умолчанию, потом сменишь!)
echo "root:gentoo" | chpasswd

echo "--- ГОТОВО! Можно перезагружаться ---"
EOF

chmod +x /mnt/gentoo/final_step.sh
chroot /mnt/gentoo /final_step.sh
