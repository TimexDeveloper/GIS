mount /dev/sda2 /mnt/gentoo
mount --rbind /dev /mnt/gentoo/dev
mount --rbind /sys /mnt/gentoo/sys
mount --types proc /proc /mnt/gentoo/proc
chroot /mnt/gentoo /bin/bash
source /etc/profile
