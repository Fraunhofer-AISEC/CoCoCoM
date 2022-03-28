#!/bin/sh
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

# Description: This script is added to the initramfs and obtains the key to
# decrypt the root partition from the SEV secret area.

PREREQ=""
prereqs() {
  echo "$PREREQ"
}

case $1 in
prereqs)
  prereqs
  exit 0
  ;;
esac

echo "Extracting SEV-Secret..."

ls -la /cryptroot/keyfiles

# name stems from crypt partition name - if the name changes, the initramfs must be updated
dd if=/dev/mem bs=4096 skip=2060 count=1 2>/dev/null | dd bs=1 skip=40 count=100 2>/dev/null | base64 -d >/cryptroot/keyfiles/root_crypt.key

# manually decrypt disk
cryptsetup open /dev/sda2 -d /cryptroot/keyfiles/root_crypt.key root_crypt
vgchange -ay