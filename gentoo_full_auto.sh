#!/bin/bash
set -e

DISK="/dev/sda"

echo ">>> 1. Creating partitions with fdisk..."
swapoff -a || true

# Команды для fdisk: 
# o - новая таблица DOS
# n, p, 1, default, +4G - Swap
# t, 82 - тип Swap
# n, p, 2, default, default - Root
# a, 2 - сделать Root загрузочным
# w - записать
printf "o\nn\np\n1\n\n+4G\nt\n82\nn\np\n2\n\n\na\n2\nw\n" | fdisk $DISK

echo ">>> 2. Forcing kernel to see new partitions..."
sync
partprobe $DISK || true
sleep 3 # Даем системе "протрезветь"

echo ">>> 3. Formatting..."
# Если тут всё равно ошибка, значит диск занят или не создался
mkswap ${DISK}1
swapon ${DISK}1
mkfs.ext4 -F ${DISK}2
mount ${DISK}2 /mnt/gentoo
cd /mnt/gentoo

echo ">>> 4. Downloading Stage3..."
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc/stage3-amd64-desktop-openrc-20260215T164556Z.tar.xz -O stage3.tar.xz
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

echo ">>> 6. Internal Install (Chroot)..."
cat <<EOF > /mnt/gentoo/install.sh
#!/bin/bash
source /etc/profile

# Repository config
mkdir -p /etc/portage/repos.conf
cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf

echo ">>> Syncing portage (Websync)..."
emerge-webrsync

# Select Profile (Desktop 23.0)
eselect profile set default/linux/amd64/23.0/desktop

echo ">>> Installing GRUB and Kernel (The long part)..."
# Ставим GRUB принудительно, чтобы команда появилась
CONFIG_PROTECT="-*" emerge --ask=n sys-boot/grub sys-kernel/gentoo-kernel-bin net-misc/dhcpcd

echo ">>> Configuring GRUB..."
grub-install --target=i386-pc $DISK
grub-mkconfig -o /boot/grub/grub.cfg

# Fstab and Finalize
echo "${DISK}2 / ext4 noatime 0 1" > /etc/fstab
echo "${DISK}1 none swap sw 0 0" >> /etc/fstab
rc-update add dhcpcd default
echo "root:gentoo" | chpasswd

echo ">>> SUCCESS! Reboot now."
EOF

chmod +x /mnt/gentoo/install.sh
chroot /mnt/gentoo /install.sh
