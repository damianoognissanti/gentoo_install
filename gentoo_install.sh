#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "This script must run as root."
    exit 1
fi

### START: Set username, password, mount dir, subvolume name and UUIDs.
USERNAME="damiano"
PASSWORD="changeme"
MNT="/mnt/gentoo"
DATE=$(date +"%Y%m%d-%H%M")
SNAME="gentoo-$DATE" # We use SNAME as hostname, so avoid underscores.
BOOTDEV="/dev/nvme0n1p1"
ROOTDEV="/dev/nvme0n1p2"
BUUID=$(blkid -s UUID -o value "$BOOTDEV")
RUUID=$(blkid -s UUID -o value "$ROOTDEV")
### END: Set username, password, mount dir, subvolume name and UUIDs.

### START: Unmount everything and create mountpoint.
if mountpoint -q "$MNT/boot"; then
    umount -R "$MNT/boot"
fi
if mountpoint -q "$MNT"; then
    umount -R "$MNT"
fi
mkdir -p "$MNT"
### END: Unmount everything and create mountpoint.

### START: Create subvolumes.
mount -o subvolid=5 /dev/disk/by-uuid/"$RUUID" "$MNT"

btrfs subvolume create "$MNT/$SNAME"

# Shared top-level subvolumes mounted into the user home.
for SUBVOL in Documents Downloads Music Pictures Spel Videos Steam; do
    if [ ! -d "$MNT/$SUBVOL" ]; then
        btrfs subvolume create "$MNT/$SUBVOL"
    fi
done

umount "$MNT"

mount -o subvol="$SNAME" /dev/disk/by-uuid/"$RUUID" "$MNT"
mkdir -p "$MNT/boot"
mount /dev/disk/by-uuid/"$BUUID" "$MNT/boot"
### END: Create subvolumes.

### START: Copy and extract stage3.
shopt -s nullglob
STAGE3=(stage3*openrc*.tar.xz)
shopt -u nullglob

if [ "${#STAGE3[@]}" -ne 1 ]; then
    echo "Expected exactly one stage3*openrc*.tar.xz in the current directory."
    exit 1
fi

cp -a "${STAGE3[0]}" "$MNT/"
cd "$MNT"
tar xpvf "$(basename "${STAGE3[0]}")" --xattrs-include='*.*' --numeric-owner
rm -f stage3*openrc*.tar.xz
### END: Copy and extract stage3.

### START: Initial configuration of system.
cp /etc/resolv.conf "$MNT/etc/"
ln -sf ../usr/share/zoneinfo/Europe/Stockholm "$MNT/etc/localtime"
sed -i -e 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "$MNT/etc/locale.gen"

cat <<EOF >> "$MNT/etc/portage/make.conf"
MAKEOPTS="-j4 -l5"
FEATURES="getbinpkg binpkg-request-signature"
ACCEPT_LICENSE="*"
EOF

sed -i -e 's/^priority = 1/priority = 9999/' "$MNT/etc/portage/binrepos.conf/gentoobinhost.conf"

mkdir -p \
  "$MNT/etc/portage/package.accept_keywords" \
  "$MNT/etc/portage/package.use"

cat <<EOF > "$MNT/etc/portage/package.accept_keywords/game-device-udev-rules"
games-util/game-device-udev-rules ~amd64
EOF

cat <<EOF > "$MNT/etc/portage/package.use/installkernel"
# required by sys-kernel/gentoo-kernel-bin[initramfs]
sys-kernel/installkernel dracut
EOF

arch-chroot "$MNT" bash -c 'emerge-webrsync'
arch-chroot "$MNT" bash -c 'getuto'
arch-chroot "$MNT" bash -c 'eselect profile set "default/linux/amd64/23.0/desktop/plasma"'
arch-chroot "$MNT" bash -c 'locale-gen && eselect locale set en_US.utf8 && env-update'

# Kernel + firmware
cat <<EOF > "$MNT/etc/cmdline"
root=UUID=$RUUID rootflags=subvol=$SNAME rw rootfstype=btrfs
EOF
arch-chroot "$MNT" bash -c 'emerge sys-kernel/linux-firmware sys-firmware/sof-firmware sys-kernel/gentoo-kernel-bin'
### END: Initial configuration of system.

### START: Install desktop environment + important programs.
arch-chroot "$MNT" bash -c '
emerge \
  app-admin/sudo \
  app-editors/neovim \
  app-eselect/eselect-repository \
  app-office/libreoffice \
  dev-python/pip \
  dev-vcs/git \
  games-util/game-device-udev-rules \
  gui-apps/wl-clipboard \
  gui-libs/display-manager-init \
  kde-apps/ark \
  kde-apps/dolphin \
  kde-apps/ffmpegthumbs \
  kde-apps/konsole \
  kde-apps/kwalletmanager \
  kde-plasma/plasma-meta \
  media-gfx/gimp \
  media-video/vlc \
  net-dns/avahi \
  net-misc/networkmanager \
  net-print/cups \
  sys-apps/arch-chroot \
  sys-apps/flatpak \
  sys-auth/nss-mdns \
  sys-boot/efibootmgr \
  sys-boot/refind \
  sys-fs/btrfs-progs \
  www-client/google-chrome \
'
### END: Install desktop environment + important programs.

### START: Enable services.
sed -i -e 's/DISPLAYMANAGER="xdm"/DISPLAYMANAGER="sddm"/' "$MNT/etc/conf.d/display-manager"
arch-chroot "$MNT" bash -c 'rc-update add display-manager default'
arch-chroot "$MNT" bash -c 'rc-update add NetworkManager default'
arch-chroot "$MNT" bash -c 'rc-update add avahi-daemon default'
arch-chroot "$MNT" bash -c 'rc-update add cupsd default'
### END: Enable services.

### START: Create and setup user account.
arch-chroot "$MNT" useradd -m -G wheel "$USERNAME"
printf '%s:%s\n' "$USERNAME" "$PASSWORD" | arch-chroot "$MNT" chpasswd

cat <<EOF > "$MNT/home/$USERNAME/.gitconfig"
[user]
email = ognissanti@hotmail.se
name = Damiano Ognissanti
[credential]
helper = store
EOF
### END: Create and setup user account.

### START: Configure system.
cat <<EOF > "$MNT/etc/fstab"
UUID="$BUUID" /boot vfat defaults,fmask=0137,dmask=0027 0 2
UUID="$RUUID" / btrfs rw,relatime,subvol=$SNAME 0 0
UUID="$RUUID" /home/$USERNAME/Documents btrfs subvol=Documents 0 0
UUID="$RUUID" /home/$USERNAME/Downloads btrfs subvol=Downloads 0 0
UUID="$RUUID" /home/$USERNAME/Music btrfs subvol=Music 0 0
UUID="$RUUID" /home/$USERNAME/Pictures btrfs subvol=Pictures 0 0
UUID="$RUUID" /home/$USERNAME/Spel btrfs subvol=Spel 0 0
UUID="$RUUID" /home/$USERNAME/Videos btrfs subvol=Videos 0 0
UUID="$RUUID" /home/$USERNAME/.var/app/com.valvesoftware.Steam/.local/share/Steam btrfs subvol=Steam 0 0
EOF

# rEFInd replaces the old systemd-boot entry logic.
arch-chroot "$MNT" bash -c 'refind-install'

cat <<EOF > "$MNT/boot/refind_linux.conf"
"Boot with standard options" "root=UUID=$RUUID rootflags=subvol=$SNAME rw rootfstype=btrfs"
EOF

cat <<EOF > "$MNT/etc/hostname"
$SNAME
EOF

cat <<EOF > "$MNT/etc/vconsole.conf"
KEYMAP=sv-latin1
EOF

mkdir -p "$MNT/etc/sudoers.d"
cat <<EOF > "$MNT/etc/sudoers.d/wheel"
%wheel ALL=(ALL:ALL) ALL
EOF
chmod 0440 "$MNT/etc/sudoers.d/wheel"


cat <<'EOF' > "$MNT/root/setup-printer.sh"
#!/bin/bash
lpadmin -p DCPL2530DW -E -v ipp://BRWB068E66B6A27.local/ipp/print -m everywhere
lpoptions -d DCPL2530DW
EOF
chmod +x "$MNT/root/setup-printer.sh"

echo "To install printer: After first reboot, run /root/setup-printer.sh as root."

# Needed for .local printer discovery.
sed -i -e 's/^hosts:.*/hosts:      mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns/' "$MNT/etc/nsswitch.conf"

# Create mountpoints for the fstab entries.
mkdir -p \
  "$MNT/home/$USERNAME/Documents" \
  "$MNT/home/$USERNAME/Downloads" \
  "$MNT/home/$USERNAME/Music" \
  "$MNT/home/$USERNAME/Pictures" \
  "$MNT/home/$USERNAME/Spel" \
  "$MNT/home/$USERNAME/Videos" \
  "$MNT/home/$USERNAME/.var/app/com.valvesoftware.Steam/.local/share/Steam"

arch-chroot "$MNT" bash -c "chown -R $USERNAME:$USERNAME /home/$USERNAME"
### END: Configure system.

### START: Flatpak.
arch-chroot "$MNT" bash -c 'flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo'
arch-chroot "$MNT" bash -c 'flatpak install -y flathub com.valvesoftware.Steam'
### END: Flatpak.

