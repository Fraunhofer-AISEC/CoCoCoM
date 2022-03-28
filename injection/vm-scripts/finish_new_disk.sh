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

# Description: This script cleans up the previously configured initrd. It
# creates a key and configures it to be used for decryption of the disk in
# the initramfs.

set -e

SCRIPT_PATH=$(dirname "$0")
KEY_PATH="/root/root.key.backup"
FAKE_KEY_PATH="/root/root.key"
# we assume we only have one disk for this script
ROOT_PARTITION="/dev/sda2"
BOOT_PARTITION="/dev/sda1"

if [ $# -ne 1 ]; then
  echo "Requires exactly one argument: the password for the encrypted partition"
  exit 1
fi

PASSWD="$1"

#-----------------------------------------------------------------------------
# confirm vm
echo "DO NOT RUN ON HOST - this could permanently damage your system."
echo "Consider making a backup of your current VM just to be safe."
echo -n "Are you sure this script is running inside of a VM and you want to continue?[y/N]"
read line
if [[ "${line^}" != "Y" ]]; then
  echo "Stopped."
  exit 0
fi
# confirm root
if [ "$EUID" -ne 0 ]; then
  echo "Please run script as root."
  exit 1
fi


# mount boot
echo "[STATUS] Mounting boot."
mkdir -p /boot
mount "$BOOT_PARTITION" /boot


# create key
echo "[STATUS] Creating key..."
dd if=/dev/urandom bs=1 count=64 of="$KEY_PATH" conv=excl,fsync
chmod 600 "$KEY_PATH"
echo FAIL >"$FAKE_KEY_PATH"
chmod 600 "$FAKE_KEY_PATH"


# add key
echo "[STATUS] Adding key to partition $ROOT_PARTITION..."
echo "$PASSWD" | cryptsetup luksAddKey "$ROOT_PARTITION" "$KEY_PATH" --pbkdf pbkdf2

# Decrypt partition using created key, no more pw prompt
# use the second key slot (not 0), since ours is in key slot 1 - greatly speeds up decryption process
UUID=$(cat /etc/crypttab | awk '{print $2}')
echo "root_crypt "$UUID" "$FAKE_KEY_PATH" luks,discard,key-slot=1" >/etc/crypttab
cat /etc/crypttab

# add key to initrd
echo "KEYFILE_PATTERN=$FAKE_KEY_PATH" >>/etc/cryptsetup-initramfs/conf-hook
echo UMASK=0077 >>/etc/initramfs-tools/initramfs.conf

# add script that extracts SEV-secret
cp "$SCRIPT_PATH/initramfs-premount.sh" /etc/initramfs-tools/scripts/init-premount/
# add base64 tool to initramfs
sed -i -e '/copy_exec \/sbin\/cryptsetup/a copy_exec \/usr\/bin\/base64' /usr/share/initramfs-tools/hooks/cryptroot


# update initramfs
# this also uses the new fstab / cryptsetup configurations and cleans it up
update-initramfs -u
chmod 644 /boot/init*


# verify initramfs key
if [ $(lsinitramfs /boot/initrd.img-* | grep cryptroot/keyfiles | wc -l) -lt 2 ]; then
  echo "[ERROR] No key detected in initramfs. This disk will most likely not boot successfully or without additional password prompts / manual steps."
else
  echo "[Success] The iniramfs was successfully updated. Disk setup is complete."
  base64key=$(base64 -w 0 /root/root.key.backup)
  echo "IMPORTANT: store this key somewhere save (not inside VM!)"
  echo "$base64key"
fi

