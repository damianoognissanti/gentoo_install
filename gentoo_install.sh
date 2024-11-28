#!/bin/bash
set -e
if [ "$EUID" -ne 0 ]
then echo "This script must run as root."
    exit
fi

### START: Set subvolume name and UUIDs.
DATE=$(date +"%Y%m%d_%H%M")
SNAME="gentoo_$DATE"
RUUID="XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
BUUID="XXXX-XXXX"
### END: Set subvolume name and UUIDs.

### START: Unmount everything and create mountpoints.
if mountpoint /mnt/boot
then
    umount -R /mnt/boot
fi
if mountpoint /mnt
then
    umount -R /mnt
fi
if mountpoint /home/damiano/Mount
then
    umount -R /home/damiano/Mount
fi
mkdir -p /home/damiano/Mount
mkdir -p /mnt
### END: Unmount everything and create mountpoints.

### START: Create subvolume for next generation.
mount /dev/disk/by-uuid/"$RUUID" /home/damiano/Mount/
btrfs subvolume create /home/damiano/Mount/"$SNAME" 
mount /dev/disk/by-uuid/"$RUUID" -o subvol="$SNAME" /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-uuid/"$BUUID" /mnt/boot/
mount -o remount,rw /dev/disk/by-uuid/"$BUUID" /mnt/boot/
### END: Create subvolume for next generation.

###  START: Copy and extract stage3
cp -a /home/damiano/Mount/gentoo-stage3/stage3*systemd* /mnt/
cd /mnt/
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
rm -r stage3*
# Copy portage settings
#cp -arv /home/damiano/Mount/gentoo-stage3/portage/. /mnt/etc/portage
###  END: Copy and extract stage3

### START: Initial configuration of system.
# Copy resolv file so that internet works
sudo cp /etc/resolv.conf /mnt/etc/
# Setup profile and locale
ln -sf ../usr/share/zoneinfo/Europe/Stockholm /mnt/etc/localtime
sed -i -e 's/^#en_US.UTF.*/en_US.UTF-8 UTF-8/g' /mnt/etc/locale.gen 

cat <<EOF >> /mnt/etc/portage/make.conf 
MAKEOPTS="-j4 -l5"
FEATURES="getbinpkg binpkg-request-signature"
ACCEPT_LICENSE="*"
EOF

cat <<EOF > /mnt/etc/portage/package.accept_keywords/sstp 
# required by networkmanager-sstp (argument)
=net-vpn/networkmanager-sstp-1.3.2 ~amd64
EOF

cat <<EOF > /mnt/etc/portage/package.use/keepassxc 
# Browser integration
app-admin/keepassxc browser
EOF

sed -i -e 's/^priority = 1/priority = 9999/g' /mnt/etc/portage/binrepos.conf/gentoobinhost.conf

arch-chroot /mnt bash -c 'emerge-webrsync'
arch-chroot /mnt bash -c 'getuto'
arch-chroot /mnt bash -c 'eselect profile set "default/linux/amd64/23.0/desktop/gnome/systemd"'
arch-chroot /mnt bash -c 'locale-gen'
arch-chroot /mnt bash -c 'eselect locale set "en_US.utf8"'
# Install kernel
arch-chroot /mnt bash -c 'emerge sys-kernel/linux-firmware sys-firmware/sof-firmware sys-kernel/gentoo-kernel-bin'
### END: Initial configuration of system.

### START: Install desktop environment + important programs
arch-chroot /mnt bash -c 'emerge gnome-extra/cinnamon www-client/google-chrome x11-terms/gnome-terminal app-admin/keepassxc mail-client/thunderbird-bin media-video/pipewire media-video/wireplumber sys-auth/rtkit app-admin/sudo sys-auth/nss-mdns app-shells/fzf app-editors/neovim x11-misc/xclip dev-vcs/git sys-fs/btrfs-progs sys-apps/arch-chroot net-vpn/networkmanager-sstp'
### END: Install desktop environment + important programs

### START: Enable services
arch-chroot /mnt bash -c 'systemctl enable gdm'
arch-chroot /mnt bash -c 'systemctl enable NetworkManager'
arch-chroot /mnt bash -c 'systemctl enable avahi-daemon'
### END: Enable services

### START: Create and setup user account
# Password set to "password", change with passwd after install.
# You can also create a password here with 
# perl -e 'print crypt("YourPassword", "YourSalt"),"\n"'
arch-chroot /mnt env -i useradd -p "shY2thr3eF5bs" -m -G wheel,pipewire damiano
cat <<EOF > /mnt/home/damiano/.gitconfig
[user]
email = ognissanti@hotmail.se
name = Damiano Ognissanti
[credential]
helper = store
EOF
### END: Create and setup user account

### START: Configure system.
# Setup pipewire
mkdir -p /mnt/etc/pipewire/
mkdir -p /mnt/home/damiano/.config/pipewire/
cp /mnt/usr/share/pipewire/pipewire.conf /mnt/etc/pipewire/pipewire.conf
cp /mnt/usr/share/pipewire/pipewire.conf /mnt/home/damiano/.config/pipewire/pipewire.conf
mkdir -p /mnt/home/damiano/.config/systemd/user/{default.target.wants,sockets.target.wants}
ln -s /usr/lib/systemd/user/pulseaudio.socket /mnt/home/damiano/.config/systemd/user/sockets.target.wants/pulseaudio.socket 
ln -s /usr/lib/systemd/user/pulseaudio.service /mnt/home/damiano/.config/systemd/user/default.target.wants/pulseaudio.service 
arch-chroot /mnt bash -c 'chown -R damiano:damiano /home/damiano/'

cat <<EOF > /mnt/etc/fstab
UUID="$RUUID" / btrfs rw,relatime,subvol=/$SNAME 0 1
UUID="$BUUID" /boot vfat defaults,fmask=0137,dmask=0027 0 2
EOF

# Store kernel name for boot entry
LINUX=$(ls /mnt/lib/modules)
cat <<EOF > /mnt/boot/loader/entries/$SNAME.conf
title   $SNAME
linux   /kernel-$LINUX
initrd  /initramfs-$LINUX.img
options root=UUID=$RUUID rootflags=subvol=$SNAME rw rootfstype=btrfs i915.enable_psr=0
EOF

cat <<EOF > /mnt/boot/loader/loader.conf
default $SNAME.conf
timeout 5
console-mode keep
EOF

# Hostname can't have underscores and ${VAR//_} removes all underscores from variable
#${SNAME//_}
cat <<EOF > /mnt/etc/hostname
gentoo
EOF

cat <<EOF > /mnt/etc/vconsole.conf
KEYMAP=sv-latin1
EOF

mkdir -p /mnt/etc/sudoers.d/
cat <<EOF >  /mnt/etc/sudoers.d/wheel
%wheel ALL=(ALL:ALL) ALL
EOF

sed -i -e 's/^hosts:.*/hosts:      mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns/g' /mnt/etc/nsswitch.conf

### END: Configure system.
set +e
