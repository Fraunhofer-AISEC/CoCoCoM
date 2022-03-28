#!/bin/bash
# Copyright 2022 Joana Pecholt, Fraunhofer AISEC
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

# Description: this script builds and generates all components required for
# AMD'S OVMF. This includes grub and a pgp key(ring)

set -e

SOURCE_DIR=$(realpath $(dirname "$0"))
BASE_PATH=$(git -C "$SOURCE_DIR" rev-parse --show-toplevel)/build

GRUB_BRANCH="master"
GRUB_COMMIT="3ffd708dd"

OVMF_BRANCH="master"
OVMF_COMMIT="3b769c5110"

GRUB_SCRIPT="$BASE_PATH/injection/edk2/OvmfPkg/AmdSev/Grub/grub.sh"
GRUB_CFG="$BASE_PATH/injection/edk2/OvmfPkg/AmdSev/Grub/grub.cfg"

PUB_KEY_PATH="$BASE_PATH/injection/pubkey.asc"
KEY_CONFIG="$BASE_PATH/injection/dummy-key-config"
KEY_NAME="Dummy-key"
KEY_PW="password"
KEYRING="$BASE_PATH/injection/sev-keyring.pgp"

compile_amd_ovmf() {
  # removing previous builds just to be sure it rebuilds
  rm -f "$BASE_PATH/edk2/OvmfPkg/AmdSev/Grub/grub.efi" "$BASE_PATH/edk2/Build/AmdSev/DEBUG_GCC5/FV/OVMF.fd"
  # Builds AMD SEV-specific OVMF
  build -n $(nproc) -a X64 -t GCC5 -p OvmfPkg/AmdSev/AmdSevX64.dsc
}

#-----------------------------------------------------------------------------


# create pgp key
# Creates key with which kernel and initrd will be signed later
# This key must be built into the OVMF if signatures are to be checked
# check for existing
if test -f "$PUB_KEY_PATH"; then
  echo -e "[STATUS] Found previously created key (ring). Skipping."
else
  echo -e "\n\n[STATUS] Creating new dummy key..."
  # create custom key ring
  gpg --no-default-keyring --keyring "$KEYRING" --fingerprint
  #(see  https://www.gnupg.org/documentation/manuals/gnupg/Unattended-GPG-key-generation.html)
  # create key config
  cat >"$KEY_CONFIG" <<EOF
  Key-Type: default
  Subkey-Type: default
  Name-Real: $KEY_NAME
  Name-Comment: Key to sign kernel
  Name-Email: test@example.com
  Expire-Date: 0
  Passphrase: $KEY_PW
EOF
  # create priv key
  res=$(gpg --no-default-keyring --keyring "$KEYRING" --batch --generate-key "$KEY_CONFIG" 2>&1 | grep "revocation certificate")
  # move automatically created revocation cert to build dir
  revcert=$(echo "$res" | sed -e "s/.*'\(.*\)'/\1/")
  mv "$revcert" "$BASE_PATH/injection"
  # get pub key
  gpg --no-default-keyring --keyring "$KEYRING" --export "$KEY_NAME" >"$PUB_KEY_PATH"
fi


# build custom grub for AMD's OVMF
cd "$BASE_PATH/injection"
if test -d grub; then
  echo -e "[STATUS] Found existing custom grub. Skipping build."
else
  echo -e "\n\n[STATUS] Building custom grub"
  mkdir -p grub
  cd grub
  # get repo
  git clone -b "$GRUB_BRANCH" --single-branch https://git.savannah.gnu.org/git/grub.git
  cd grub
  git checkout "$GRUB_COMMIT"
  # build
  ./bootstrap
  ./configure --prefix="$BASE_PATH/injection/grub/grub-install" --host=x86_64-linux-gnu --with-platform=efi --target=x86_64-linux-gnu
  make -j $(nproc)
  make install
fi


# build AMD's custom OVMF
cd "$BASE_PATH/injection"
# check if exists
if test -d edk2; then
  echo -e "[STATUS] Found existing OVMF for injection. Skipping."
else
  echo -e "\n\n[STATUS] Building OVMF for injection"
  # get repo
  git clone -b "$OVMF_BRANCH" --single-branch https://github.com/tianocore/edk2.git
  cd edk2
  git checkout "$OVMF_COMMIT"
  git submodule update --init --recursive
  # build
  make -j $(nproc) -C BaseTools/

  # Configure grub.sh to include signature key (does not need to be used)
  # remove unnecessary modules
  sed -i -e '/linuxefi/d' "$GRUB_SCRIPT"
  sed -i -e '/sevsecret/d' "$GRUB_SCRIPT"
  # add key path
  sed -i -e '/remove_efi=1/a GPG_KEY="'$PUB_KEY_PATH'"' "$GRUB_SCRIPT"
  # add key as trusted key to grub
  sed -i -e '/^.*${GRUB_MODULES}/i\           --pubkey "$GPG_KEY" \\' "$GRUB_SCRIPT"
  # add further required modules
  sed -i -e 's/${GRUB_MODULES}/${GRUB_MODULES}\\\n           hashsum all_video halt gcry_sha512 gcry_dsa gcry_rsa/' "$GRUB_SCRIPT"

  source ./edksetup.sh --reconfig
  # Updating grub with possible changes to the configs
  cp "$SOURCE_DIR/../injection/grub.cfg" "$GRUB_CFG"
  # use custom grub
  export PATH="$BASE_PATH/injection/grub/grub-install/bin:$PATH"

  # compile AMD's OVMF without signature check (for injection)
  sed -i -e 's/^\(set check_signatures=\).*/\1no/' "$GRUB_CFG"
  compile_amd_ovmf
  cp Build/AmdSev/DEBUG_GCC5/FV/OVMF.fd "$BASE_PATH/injection/OVMF.nosig.fd"

  # recompile AMD's OVMF with signature check enforced (for injection)
  sed -i -e 's/^\(set check_signatures=\).*/\1enforce/' "$GRUB_CFG"
  compile_amd_ovmf
  cp Build/AmdSev/DEBUG_GCC5/FV/OVMF.fd "$BASE_PATH/injection/OVMF.fd"
fi
