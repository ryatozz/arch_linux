#!/bin/bash

set -e

DISK="/dev/sda"
ENC_DISK="/dev/sdb"
HOSTNAME="archlinux"
USERNAME="ryatozz"

echo "[*] Vérification et démontage des partitions..."
mount | grep "$DISK" | awk '{print $3}' | xargs -r umount -l
swapoff -a

echo "[*] Suppression de l'ancienne table de partitions..."
wipefs -a "$DISK"
sgdisk --zap-all "$DISK"

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
echo -n "archlinux" | cryptsetup luksFormat "$ENC_DISK" --type luks1
echo "archlinux" | cryptsetup open "$ENC_DISK" cryptroot 

pvcreate /dev/mapper/cryptroot
vgcreate vg0 /dev/mapper/cryptroot
lvcreate -L 5G vg0 -n shared_folder

mkfs.ext4 /dev/vg0/shared_folder

mkdir /mnt/shared_folder
mount /dev/vg0/shared_folder /mnt/shared_folder

echo "[*] Installation de base..."
pacstrap /mnt base linux linux-firmware lvm2 sudo vim git wget gcc make gdb base-devel virtualbox virtualbox-host-modules-arch

mkdir -p /mnt/proc /mnt/sys /mnt/dev /mnt/dev/pts

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF
  echo "$HOSTNAME" > /etc/hostname
  hostnamectl set-hostname $HOSTNAME
  ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
  hwclock --systohc
  echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
  echo "KEYMAP=fr" > /etc/vconsole.conf
  locale-gen

  useradd -m -G wheel -s /bin/bash $USERNAME
  echo "$USERNAME:azerty123" | chpasswd
  echo "root:azerty123" | chpasswd
  echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

  pacman -Syu --noconfirm xorg-server xorg-xinit sddm hyprland alacritty neovim firefox

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

  systemctl enable sddm

  groupadd partage
  usermod -aG partage $USERNAME
  mkdir /home/$USERNAME/shared_folder
  chown -R $USERNAME:partage /home/$USERNAME/shared_folder
  chmod -R 770 /home/$USERNAME/shared_folder

  pacman -S --noconfirm samba
  echo "[shared_folder]" >> /etc/samba/smb.conf
  echo "path = /home/$USERNAME/shared_folder" >> /etc/samba/smb.conf
  echo "guest ok = yes" >> /etc/samba/smb.conf
  systemctl enable smb
EOF

echo "[*] Installation terminée ! Redémarrage..."
reboot
