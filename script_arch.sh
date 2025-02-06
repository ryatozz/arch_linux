#!/bin/bash

set -e

DISK="/dev/sda"
ENC_DISK="/dev/sdb"
HOSTNAME="archlinux"
USERNAME="ryatozz"

echo "[*] Partitionnement du disque principal..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 512MiB
parted -s "$DISK" mkpart primary ext4 512MiB 100%

mkfs.fat -F32 "${DISK}1"
mkfs.ext4 "${DISK}2"

mount "${DISK}2" /mnt
mkdir /mnt/boot
mount "${DISK}1" /mnt/boot

echo "[*] Chiffrement du disque secondaire..."
echo -n "archlinux" | cryptsetup luksFormat "$ENC_DISK"
cryptsetup open "$ENC_DISK" cryptroot <<< "archlinux" # Correction ici

pvcreate /dev/mapper/cryptroot
vgcreate vg0 /dev/mapper/cryptroot
lvcreate -L 10G vg0 -n storage
lvcreate -L 5G vg0 -n share

mkfs.ext4 /dev/vg0/storage
mkfs.ext4 /dev/vg0/share

mkdir /mnt/storage
mkdir /mnt/share
mount /dev/vg0/storage /mnt/storage
mount /dev/vg0/share /mnt/share

echo "[*] Installation de base..."
pacstrap /mnt base linux linux-firmware lvm2 sudo vim git wget

pacstrap /mnt gcc make gdb base-devel

pacstrap /mnt virtualbox virtualbox-host-modules-arch

# Création des dossiers /mnt/proc, /mnt/sys, /mnt/dev et /mnt/dev/pts
mkdir -p /mnt/proc
mkdir -p /mnt/sys
mkdir -p /mnt/dev
mkdir -p /mnt/dev/pts

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF
  echo "$HOSTNAME" > /etc/hostname
  hostnamectl set-hostname $HOSTNAME
  ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
  hwclock --systohc
  echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
  echo "KEYMAP=fr" > /etc/vconsole.conf
  locale-gen

  # Création de l'utilisateur
  useradd -m -G wheel -s /bin/bash $USERNAME
  echo "$USERNAME:azerty123" | chpasswd
  echo "root:azerty123" | chpasswd
  echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

  # Installation de l'environnement graphique
  pacman -Syu --noconfirm xorg-server xorg-xinit sddm hyprland alacritty neovim firefox

  # Configuration d'Hyprland
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

  # Configuration du dossier partagé
  groupadd partage
  usermod -aG partage $USERNAME
  chown -R $USERNAME:partage /home/$USERNAME/share
  chmod -R 770 /home/$USERNAME/share

  # Activation de Samba
  pacman -S --noconfirm samba
  mkdir /home/$USERNAME/share
  echo "[share]" >> /etc/samba/smb.conf
  echo "path = /home/$USERNAME/share" >> /etc/samba/smb.conf
  echo "guest ok = yes" >> /etc/samba/smb.conf
  systemctl enable smb
EOF

echo "[*] Installation terminée ! Redémarrez manuellement." # Message à l'utilisateur
