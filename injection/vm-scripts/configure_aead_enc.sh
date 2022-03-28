#!/bin/bash
# Copyright 2020-2021 Joana Pecholt, Fraunhofer AISEC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Description: This script formats the new disk, transfers all files to it and
# configures its initrd accordingly.

set -e

if [ $# -ne 1 ]; then
  echo "Require exactly one argument: password decrypting the root partition"
  exit 1
fi
# Must be injected during SEV-VM launch
PASSWD="$1"

# will be configured later
DISK=""

#-------------------------------------------------------------------------------------
# confirm vm
echo "DO NOT RUN ON HOST - this could permanently damage your system."
echo "Consider making a backup of your VM just to be safe."
echo -n "Are you sure this script is running inside of a VM and you want to continue?[y/N]"
read line
if [[ "${line^}" != "Y" ]]; then
  echo "Stopped."
  exit 1
fi


# confirm root
if [ "$EUID" -ne 0 ]; then
  echo "Please run script as root."
  exit 1
fi


# check nr kernels
echo "[STATUS] Checking number of kernels..."
if [ $(find /boot/ -name vmlinuz* | wc -l) -ne 1 ]; then
  echo "[ERROR] Make sure to have exactly one kernel / initrd installed. "
  exit 1
fi


# find disk
for x in {a..z}; do
  # crude way to look for our disk: it's the one where no other subpartitions exist yet
  if [ $(ls "/dev/sd$x"* 2>/dev/null | wc -l) -eq 1 ]; then
    DISK="sd$x"
    break
  fi
done
if [[ "$DISK" == "" ]]; then
  echo "[ERROR] Could not find target disk. Aborting."
  exit 1
fi
echo -n "Using disk $DISK - is this the right one?[y/N]"
read line
if [[ "${line^}" != "Y" ]]; then
  echo "Stopped."
  exit 1
fi


# partition disk2
echo "[STATUS] Partitioning $DISK..."
# ADAPT HERE if you want a boot partition with other size than 500MB
echo -ne "o\nY\nn\n\n\n500MB\n\nn\n\n\n\n\nw\nY\n" | gdisk "/dev/$DISK"
# Configure root (and swap) partition with integrity
echo "[STATUS] Formating root partition - this can take several minutes!"
echo "$PASSWD" | cryptsetup luksFormat -q --type luks2 --integrity hmac-sha256 "/dev/${DISK}2"
echo "$PASSWD" | cryptsetup open "/dev/${DISK}2" root_crypt
pvcreate /dev/mapper/root_crypt
vgcreate vgroot /dev/mapper/root_crypt
# ADAPT HERE if you desire more or less swap
lvcreate -l 90%FREE vgroot -n root
lvcreate -l 100%FREE vgroot -n swap

# format partitions accordingly
mkfs.ext4 "/dev/${DISK}1"
mkfs.ext4 /dev/vgroot/root
mkswap /dev/vgroot/swap


# update current initramfs
# This creates a new initramfs which should still work for the existing VM
# This adds additional tools that will be required for the initramfs of the new VM
echo "[STATUS] Updating initramfs with required crypt/integrity tools..."
# add integritysetup/integrity tools to initramfs
sed -i -e '/copy_exec \/sbin\/cryptsetup/a copy_exec \/sbin\/integritysetup' /usr/share/initramfs-tools/hooks/cryptroot
sh -c 'echo "CRYPTSETUP=y" >> /etc/cryptsetup-initramfs/conf-hook'
# force to include cryptroot, sometimes it has issues finding the encrypted partitions and conveniently optimizes the tool out
echo dm-integrity | tee -a /etc/initramfs-tools/modules
# update existing initrd (will be used as base for new system)
update-initramfs -u


# transfer files
echo "[STATUS] Transfering file system. This may take a while..."
cd /
# transfer root fs
mkdir -p .root
mount /dev/vgroot/root .root
mkdir -p .root/dev
mkdir -p .root/boot
mkdir -p .root/proc
mkdir -p .root/run
mkdir -p .root/sys
mkdir -p .root/tmp
mkdir -p .root/media
cp -ra bin etc home lib* mnt opt root sbin srv usr var .root/
# transfer kernel
mkdir -p .boot/
mount "/dev/${DISK}1" .boot
# copy kernel - initrd will be generated from existing one later
cp /boot/vmlinuz-* .boot/


# create new initramfs
echo "[STATUS] Creating new initrd based on previously updated initrd..."
UUID=$(blkid | grep "/dev/${DISK}2" | awk '{print $2}' | sed 's/"//g')
INITRD=$(ls /boot/init* | head -1)
NEW_INITRD="/.boot/$(basename $INITRD)"

# open initrd because initramfs-tools is buggy so we do this manually
mkdir /tmp/initrd
cd /tmp/initrd
# unpack initrd: we assume gzip compression
zcat "$INITRD" | cpio -idmv

# specify mounts
echo "/dev/mapper/vgroot-root / ext4 errors=remount-ro 0 1" >etc/fstab
echo "/dev/mapper/vgroot-swap none swap sw  0 0" >>etc/fstab
# decrypt correct partition
echo "root_crypt $UUID none luks,discard" >cryptroot/crypttab
# remove mention of other logical volumes
find etc/lvm/backup/ -type f -not -name 'vgroot' -delete
rm -f conf/conf.d/resume

# package modified initrd for new system
find . | cpio -o -H newc -R root:root | gzip -9 >"$NEW_INITRD"
chmod 644 "$NEW_INITRD"


# replace files copied from old disk with newly created ones
cp /tmp/initrd/etc/fstab /.root/etc
cp /tmp/initrd/cryptroot/crypttab /.root/etc
# remove mention of other logical volumes
find /.root/etc/lvm/backup/ -type f -not -name 'vgroot' -delete
rm -f /.root/etc/initramfs-tools/conf.d/resume


echo "[STATUS] Success."
echo "You can now try to boot the newly created disk using the custom OVMF."
