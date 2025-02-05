#!/bin/bash

set -e  # Arrêt en cas d'erreur

# Variables
DISK="/dev/sda"
ENC_DISK="/dev/sdb" # Disque dédié au stockage chiffré
HOSTNAME="archlinux"
USERNAME="alex"

# Partitionnement principal
echo "[*] Partitionnement du disque principal..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 512MiB
parted -s "$DISK" mkpart primary ext4 512MiB 100%

# Formater et monter les partitions
mkfs.fat -F32 "${DISK}1"
mkfs.ext4 "${DISK}2"

mount "${DISK}2" /mnt
mkdir /mnt/boot
mount "${DISK}1" /mnt/boot

# Chiffrement du disque secondaire avec LUKS + LVM
echo "[*] Chiffrement du disque secondaire..."
echo -n "archlinux" | cryptsetup luksFormat "$ENC_DISK"
echo -n "archlinux" | cryptsetup open "$ENC_DISK" cryptroot

pvcreate /dev/mapper/cryptroot
vgcreate vg0 /dev/mapper/cryptroot
lvcreate -L 9G vg0 -n storage

mkfs.ext4 /dev/vg0/storage
mkdir /mnt/storage
mount /dev/vg0/storage /mnt/storage

# Installation de base
echo "[*] Installation de base..."
pacstrap /mnt base linux linux-firmware lvm2 sudo

# Configuration du système
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF
  echo "$HOSTNAME" > /etc/hostname
  ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
  hwclock --systohc
  echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
  echo "KEYMAP=fr" > /etc/vconsole.conf
  locale-gen

  # Utilisateur
  useradd -m -G wheel -s /bin/bash $USERNAME
  echo "$USERNAME:archlinux" | chpasswd
  echo "root:archlinux" | chpasswd
  echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

  # Installation de Hyprland
  pacman -Syu --noconfirm hyprland git alacritty neovim

  # Configurer le partage
  pacman -S --noconfirm samba
  mkdir /home/$USERNAME/share
  echo "[share]" >> /etc/samba/smb.conf
  echo "path = /home/$USERNAME/share" >> /etc/samba/smb.conf
  echo "guest ok = yes" >> /etc/samba/smb.conf
  systemctl enable smb

EOF

echo "[*] Installation terminée !"
