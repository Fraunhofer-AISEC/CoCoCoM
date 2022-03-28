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

# Description: This script builds all required components, including the
# kernel, two QEMUs (for migration and injection, respectively), different
# OVMFs (migration/injection) and the sev-tool.

set -e

SOURCE_DIR=$(realpath $(dirname "$0"))
BASE_PATH=$(git -C "$SOURCE_DIR" rev-parse --show-toplevel)/build

LINUX_CONFIG="$SOURCE_DIR/config-5.7.0-3-amd64"
LINUX_BRANCH="sev-migration-v8"
LINUX_COMMIT="a70e7ea40c47"

QEMU_BRANCH="master"
QEMU_COMMIT="v6.0.0"

MIGRATION_QEMU_BRANCH="sev-migration-v1"
MIGRATION_QEMU_COMMIT="6d613bbf56"

SEV_TOOL_BRANCH="master"
SEV_TOOL_COMMIT="22c5d45"

check() {
  if dpkg-query -W -f'${Status}' "$1" 2>/dev/null | grep -q 'ok installed'; then
    echo "Found $1"
  else
    echo "Missing $1"
    exit 1
  fi
}
#-----------------------------------------------------------------------------

# check dependencies
check git
check bc
check build-essential
check libncurses-dev
check flex
check bison
check openssl
check libssl-dev
check dkms
check libelf-dev
check libudev-dev
check libpci-dev
check libiberty-dev
check autoconf
check dwarves
check libpixman-1-dev
check libglib2.0-dev
check binutils-dev
check pkg-config
check ninja-build
check make
check gcc
check g++
check automake
check wget
check uuid-dev
check libvirt-dev
check gpg
check nasm
check python3-distutils
check dosfstools
check mtools
check binutils
check gettext
check autopoint

if ! command -v mkfs.msdos >/dev/null; then
  echo "Command mkfs.msdos not found. is /sbin in PATH?"
  exit 1
fi

if ! (dpkg -l | grep -e 'libdevmapper[0-9.]\+' >/dev/null); then
  echo "Libdevmapper not found";
  exit 1
fi


# make base dir
mkdir -p "$BASE_PATH"


# build kernel
cd "$BASE_PATH"
if test -d kernel; then
  echo "[STATUS] existing kernel found. Skipping."
else
  echo -e "\n\n[STATUS] Building custom kernel"
  mkdir kernel
  cd kernel

  # get repo
  git clone -b "$LINUX_BRANCH" --single-branch https://github.com/AMDESE/linux.git
  cd linux/
  # checkout functioning commit
  git checkout "$LINUX_COMMIT"

  # configure
  cp "$LINUX_CONFIG" .config
  make olddefconfig

  # make
  make -j $(nproc) deb-pkg LOCALVERSION=-"$LINUX_BRANCH"
fi


# build sev-tool
cd "$BASE_PATH"
if test -d sev-tool; then
  echo "[STATUS] Found existing SEV-tools. Skipping."
else
  echo -e "\n\n[STATUS] Building the SEV-Tool"
  # get repo
  git clone -b "$SEV_TOOL_BRANCH" --single-branch  https://github.com/AMDESE/sev-tool.git
  cd sev-tool
  git checkout "$SEV_TOOL_COMMIT"
  # build
  autoreconf -vif && ./configure && make
fi


# build qemu for injection
mkdir -p "$BASE_PATH/injection"
cd "$BASE_PATH/injection"
if test -d qemu; then
  echo "[STATUS] Found existing QEMU for integrity. Skipping."
else
  echo -e "\n\n[STATUS] Building QEMU for injection"
  # get repo
  git clone -b "$QEMU_BRANCH" --single-branch https://github.com/qemu/qemu.git
  cd qemu
  git checkout "$QEMU_COMMIT"
  # build
  ./configure --target-list=x86_64-softmmu --enable-debug
  make -j$(nproc)
fi


# build qemu for migration
mkdir -p "$BASE_PATH/migration"
cd "$BASE_PATH/migration"
if test -d qemu; then
  echo "[STATUS] Found existing QEMU for migration. Skipping."
else
  echo -e "\n\n[STATUS] Building QEMU for migration"
  # get repo
  git clone -b "$MIGRATION_QEMU_BRANCH" --single-branch https://github.com/AMDESE/qemu.git
  cd qemu
  git checkout "$MIGRATION_QEMU_COMMIT"
  # build
  ./configure --target-list=x86_64-softmmu --enable-debug
  make -j$(nproc)
fi

# build OVMF for injection
"$SOURCE_DIR/build_injection_ovmf.sh"

#build OVMF for migration
"$SOURCE_DIR/build_migration_ovmf.sh"

echo -e "\n\n[STATUS] All components are built."
