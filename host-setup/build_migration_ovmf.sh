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

# Description: this script builds an OVMF which can be used if the VM is
# to be migrated using SEV.

set -e

SOURCE_DIR=$(realpath $(dirname "$0"))
BASE_PATH=$(git -C "$SOURCE_DIR" rev-parse --show-toplevel)/build

MIGRATION_OVMF_BRANCH="sev-migration-v1"
MIGRATION_OVMF_COMMIT="89c0166a5e"

# build basic ovmf
cd "$BASE_PATH/migration"
# check if exists
if test -d ovmf; then
  echo -e "[STATUS] Found existing OVMF for migration. Skipping."
else
  echo -e "\n\n[STATUS] Building OVMF for migration"
  # get repo
  git clone -b "$MIGRATION_OVMF_BRANCH" --single-branch https://github.com/AMDESE/ovmf.git
  cd ovmf
  git checkout "$MIGRATION_OVMF_COMMIT"
  git submodule update --init --recursive
  # build
  make -j $(nproc) -C BaseTools/
  source ./edksetup.sh --reconfig

  # compile general OVMF (for migration)
  build -DDEBUG_ON_SERIAL_PORT=TRUE -n $(nproc) -a X64 -a IA32 -t GCC5 -p OvmfPkg/OvmfPkgIa32X64.dsc
  cp Build/Ovmf3264/DEBUG_GCC5/FV/OVMF_* "$BASE_PATH/migration"
fi