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

# Description: This script installs the previously build sev-tool and
# kernel and configures it as the default. The permissions of /dev/sev
# are adapted as well.

set -e

SOURCE_DIR=$(dirname "$0")
BASE_PATH=$(git -C "$SOURCE_DIR" rev-parse --show-toplevel)/build

LINUX_BRANCH="sev-migration-v8"
GRUB_BOOT_ENTRY='Advanced options for Ubuntu>Ubuntu, with Linux 5.7.0-rc4-sev-migration-v8'


# confirm_installation
echo "This will build and install a custom kernel and make it the default kernel."
echo -n "Are you aware this might damage your system, especially if errors occur?[y/N]"
read line
if [[ "${line^}" != "Y" ]]; then
  echo "Stopped."
  exit 1
fi

# install_kernel
if ! test -d "$BASE_PATH/kernel"; then
  echo "[Error]: No kernel to install found?"
  exit 1
fi
cd "$BASE_PATH/kernel"
echo -e "\n\n[STATUS] Installing custom kernel"
# install
apt install -y ./linux-image*-"$LINUX_BRANCH"*

# set kernel as default in grub
# Save default
sed -i -e "s/^\(GRUB_DEFAULT\).*/\1=saved/" /etc/default/grub
# Create new default
grub-set-default "$GRUB_BOOT_ENTRY"
update-grub
echo "[STATUS] Installed kernel and configured grub"

# Adapt udev rules so that /dev/sev has right permissions / ownership
echo 'SUBSYSTEM=="misc", KERNEL=="sev", ACTION=="add|change", GROUP="kvm", MODE="0660"' > /etc/udev/rules.d/99-sev.rules

echo -e "\n\n[STATUS] Kernel install complete. Reboot to use the custom kernel. Verify configuration beforehand."
