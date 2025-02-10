#!/bin/bash

set -e


DISK="/dev/sda"
ENC_DISK="/dev/sdb"
HOSTNAME="archlinux"
USERNAME="ryatozz"
PASSWORD="azerty123"

echo "[*] Partitionnement du disque principal (UEFI + partition racine)..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 512MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary ext4 512MiB 100%

mkfs.fat -F32 "${DISK}1"
mkfs.ext4 "${DISK}2"

mount "${DISK}2" /mnt
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

echo "[*] Chiffrement du deuxième disque ($ENC_DISK) + LVM..."

echo -n "$PASSWORD" | cryptsetup luksFormat "$ENC_DISK" -
echo -n "$PASSWORD" | cryptsetup open "$ENC_DISK" cryptroot


pvcreate /dev/mapper/cryptroot
vgcreate vg0 /dev/mapper/cryptroot


lvcreate -L 10G vg0 -n storage

lvcreate -L 5G vg0 -n share

lvcreate -L 2G vg0 -n swap


mkfs.ext4 /dev/vg0/storage
mkfs.ext4 /dev/vg0/share
mkswap /dev/vg0/swap



echo "[*] Installation de base (pacstrap)..."
pacstrap /mnt \
  base linux linux-firmware \
  lvm2 sudo vim git wget \
  gcc make gdb base-devel \
  virtualbox virtualbox-host-modules-arch

echo "[*] Génération du fstab..."
genfstab -U /mnt >> /mnt/etc/fstab



cat <<EOF >> /mnt/etc/fstab

# Volumes chiffrés (ouvert et monté manuellement) :

#/dev/vg0/storage   /storage   ext4 defaults,noauto 0 0
#/dev/vg0/share     /share     ext4 defaults,noauto 0 0
#/dev/vg0/swap      none       swap defaults,noauto 0 0
EOF

arch-chroot /mnt /bin/bash <<EOFCHROOT

  echo "[*] Configuration de base..."
  echo "$HOSTNAME" > /etc/hostname
  hostnamectl set-hostname "$HOSTNAME"
  ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
  hwclock --systohc

  echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
  echo "KEYMAP=fr" > /etc/vconsole.conf
  sed -i 's/^#fr_FR.UTF-8 UTF-8/fr_FR.UTF-8 UTF-8/' /etc/locale.gen
  locale-gen

  # Création de l'utilisateur
  useradd -m -G wheel -s /bin/bash "$USERNAME"
  echo "$USERNAME:$PASSWORD" | chpasswd
  echo "root:$PASSWORD" | chpasswd
  echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

  ###########################################################################
  # Installation de l'environnement graphique
  ###########################################################################
  pacman -Syu --noconfirm xorg-server xorg-xinit sddm hyprland alacritty neovim firefox

  # Configuration Hyprland pour l'utilisateur
  mkdir -p /home/$USERNAME/.config/hypr
  cat <<EOT > /home/$USERNAME/.config/hypr/hyprland.conf
monitor=,preferred,auto,1
exec-once=alacritty
input {
    kb_layout=fr
    follow_mouse=1
}
general {
    gaps_in=5
    gaps_out=10
    border_size=2
    col.active_border=0xff8aadf4
    col.inactive_border=0xff1a1b26
}
EOT
  chown -R $USERNAME:$USERNAME /home/$USERNAME/.config/hypr

  # Activer le gestionnaire de session SDDM
  systemctl enable sddm

  ###########################################################################
  # Configuration du dossier partagé + Samba
  ###########################################################################
  groupadd partage
  usermod -aG partage $USERNAME

  mkdir /home/$USERNAME/share
  chown -R $USERNAME:partage /home/$USERNAME/share
  chmod -R 770 /home/$USERNAME/share

  pacman -S --noconfirm samba
  echo "[share]" >> /etc/samba/smb.conf
  echo "path = /home/$USERNAME/share" >> /etc/samba/smb.conf
  echo "guest ok = yes" >> /etc/samba/smb.conf
  systemctl enable smb

  ###########################################################################
  # Bootloader (GRUB en UEFI) + VirtualBox Guest
  ###########################################################################
  pacman -S --noconfirm grub efibootmgr virtualbox-guest-utils
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
  grub-mkconfig -o /boot/grub/grub.cfg
  systemctl enable vboxservice

  ###########################################################################
  # Installation et activation d'un gestionnaire réseau (NetworkManager)
  ###########################################################################
  pacman -S --noconfirm networkmanager
  systemctl enable NetworkManager

EOFCHROOT

echo "[*] Installation terminée ! Redémarrage dans 10 secondes..."
sleep 10
reboot
