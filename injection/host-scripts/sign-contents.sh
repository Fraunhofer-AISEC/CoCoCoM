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

# Description: This script signs the contents (kernel and initrd) of the
# provided directory using the previously created dummy key.

set -e

SOURCE_DIR=$(dirname "$0")
BASE_PATH=$(git -C "$SOURCE_DIR" rev-parse --show-toplevel)/build/injection

PUB_KEY_PATH="$BASE_PATH/pubkey.asc"
KEY_NAME="Dummy-key"
KEY_PW="password"
KEYRING="$BASE_PATH/sev-keyring.pgp"
#-----------------------------------------------------------------------------
if [ $# != 1 ]; then
  echo "Require one argument, namely directory conatining files to be signed"
  exit 1
fi

if test ! -d $1; then
  echo "Argument is not a directory."
  exit 1
fi

directory="$1"

# check_key
echo "[STATUS] Checking for key..."
key_id=$(gpg --no-default-keyring --keyring "$KEYRING" --armor --list-keys "$KEY_NAME" 2>/dev/null | head -2 | tail -1 | awk '{print $1}')
if [[ "$key_id" == "" ]]; then
  echo "Couldn't find a key with name $KEY_NAME. "
  echo "Are you sure you are on the same system where you created the OVMF (and key)?"
  exit 1
fi


# sign
echo "[STATUS] Signing contents of directory ..."
# signatures are placed right next to file
for file in $(find "$directory" -maxdepth 1 -not -type d); do
  echo "Signing $file ..."
  gpg --no-default-keyring --keyring "$KEYRING" --pinentry-mode loopback --passphrase "$KEY_PW" --detach-sign -u "$KEY_NAME" "$file"
done
