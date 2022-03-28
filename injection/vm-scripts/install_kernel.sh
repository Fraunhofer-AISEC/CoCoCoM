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


# Description: This script installs the provided kernel, configures it as the
# default and removes older kernels after reboot.

set -e

LINUX_BRANCH="sev-migration-v8"
GRUB_BOOT_ENTRY="Advanced options for Debian GNU/Linux>Debian GNU/Linux, with Linux 5.7.0-rc4-sev-migration-v8"

# ---------------------------------------------------------------------------

if [ $# -ne 1 ]; then
  echo "Run the script with the path to the kernel as the only argument"
  exit 1
fi

if test ! -f "$1"; then
  echo "Not valid path?"
  exit 1
fi

#confirm root
if [ "$EUID" -ne 0 ]; then
  echo "Please run script as root."
  exit 1
fi

# install kernel
echo -e "\n\n[STATUS] Installing custom kernel"
# install
apt install -y "$1"

# set kernel as default in grub
# Save default
sed -i -e "s/^\(GRUB_DEFAULT\).*/\1=saved/" /etc/default/grub
# Create new default
grub-set-default "$GRUB_BOOT_ENTRY"
update-grub

# configure network - will make network setup more stable
# remove references to previous network interface
sed -i -e '/.*enp[0-9]\+.*/d' /etc/network/interfaces
sed -i -e '/.*ens[0-9]\+.*/d' /etc/network/interfaces
# Configure dhcp
echo -e "auto /en*=en\niface en inet dhcp" | tee -a /etc/network/interfaces