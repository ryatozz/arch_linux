#!/bin/bash

set -e

###############################################################################
# Variables
###############################################################################
DISK="/dev/sda"
ENC_DISK="/dev/sdb"
HOSTNAME="archlinux"
USERNAME="ryatozz"
PASSWORD="azerty123"   # Mot de passe pour root et user

###############################################################################
# 1. Partitionnement du disque principal (pour /)
###############################################################################
echo "[*] Partitionnement du disque principal..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 512MiB
parted -s "$DISK" mkpart primary ext4 512MiB 100%

mkfs.fat -F32 "${DISK}1"
mkfs.ext4 "${DISK}2"

mount "${DISK}2" /mnt
mkdir /mnt/boot
mount "${DISK}1" /mnt/boot

###############################################################################
# 2. Chiffrement du disque secondaire + LVM dessus
###############################################################################
echo "[*] Chiffrement du disque secondaire..."
# Mot de passe en clair "azerty123" juste pour l'exemple
echo -n "$PASSWORD" | cryptsetup luksFormat "$ENC_DISK" -
echo -n "$PASSWORD" | cryptsetup open "$ENC_DISK" cryptroot

# Création du PV LVM, du VG et des LVs
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

###############################################################################
# 3. Installation de base
###############################################################################
echo "[*] Installation de base (pacstrap) ..."
pacstrap /mnt base linux linux-firmware lvm2 sudo vim git wget \
  gcc make gdb base-devel \
  virtualbox virtualbox-host-modules-arch

# Génération du fstab
genfstab -U /mnt >> /mnt/etc/fstab

###############################################################################
# 4. Configuration en chroot
###############################################################################
arch-chroot /mnt /bin/bash <<EOF
  # ------------------------------------------------
  # Configuration de base (locales, hostname, user)
  # ------------------------------------------------
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

  # ------------------------------------------------
  # Installation de l'environnement graphique
  # ------------------------------------------------
  pacman -Syu --noconfirm xorg-server xorg-xinit sddm hyprland alacritty neovim firefox

  # Configuration Hyprland
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

  # ------------------------------------------------
  # Configuration du dossier partagé + Samba
  # ------------------------------------------------
  groupadd partage
  usermod -aG partage $USERNAME
  # Petit dossier "share" dans le home
  mkdir /home/$USERNAME/share
  chown -R $USERNAME:partage /home/$USERNAME/share
  chmod -R 770 /home/$USERNAME/share

  pacman -S --noconfirm samba
  echo "[share]" >> /etc/samba/smb.conf
  echo "path = /home/$USERNAME/share" >> /etc/samba/smb.conf
  echo "guest ok = yes" >> /etc/samba/smb.conf
  systemctl enable smb

  # ------------------------------------------------
  # Installation et configuration du bootloader (GRUB)
  # ------------------------------------------------
  pacman -S --noconfirm grub efibootmgr virtualbox-guest-utils

  # Installation de grub en UEFI
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
  grub-mkconfig -o /boot/grub/grub.cfg

  # (Optionnel) Mise à jour de l’initramfs au cas où
  # mkinitcpio -P

  # ------------------------------------------------
  # Activer le service VirtualBox Guest (pour la VM invitée)
  # ------------------------------------------------
  systemctl enable vboxservice

  # ------------------------------------------------
  # Installation et activation d'un gestionnaire réseau
  # (recommandé pour avoir le net en interface graphique)
  # ------------------------------------------------
  pacman -S --noconfirm networkmanager
  systemctl enable NetworkManager

EOF

###############################################################################
# 5. Fin de l'installation
###############################################################################
echo "[*] Installation terminée ! Redémarrage dans 10 secondes..."
sleep 10
reboot
