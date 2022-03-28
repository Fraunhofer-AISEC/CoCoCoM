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

# Description: This script launches an SEV-encrypted VM in the background
# on this machine.

set -e

SOURCE_DIR=$(dirname "$0")
QEMU=$(git -C "$SOURCE_DIR" rev-parse --show-toplevel)/build/injection/qemu/build/qemu-system-x86_64

while test $# -gt 0; do
  case "$1" in
  -h | --help)
    echo "Tool to start SEV-encrypted VMs on this machine."
    echo " "
    echo "Run with: ./launch.sh [-f, --flag <value>]"
    echo "-h, --help                         Show this help"
    echo "-d, --directory </path/to/dir>     Directory in which to VM image and OVMF are located (locally)"
    echo "-o, --policy <policy>              Policy to be used for VM launch (eg 0)."
    echo "-n, --name <vm-name>               Name of VM to be launched"
    exit 0
    ;;
  -d | --directory)
    shift
    # remove trailing slash
    BASE_PATH="${1%/}"
    if [ ! -d "$BASE_PATH" ]; then
      echo "$BASE_PATH is not an existing directory."
      exit 1
    fi
    shift
    ;;
  -o | --policy)
    shift
    POLICY=$1
    # hex or base10 encoded
    re='^(0x)*[0-9]+$'
    if ! [[ "$POLICY" =~ $re ]]; then
      echo "Policy is not a number."
      exit 1
    fi
    shift
    ;;
  -n | --name)
    shift
    NAME=$1
    vm_pid=$(pidof $NAME || true)
    if [[ "$vm_pid" != "" ]]; then
      echo "ERROR: VM with name $name already running."
      exit 1
    fi
    shift
    ;;
  *)
    echo "Detected unknown command or unnecessary argument? ($1)"
    exit 1
    ;;
  esac
done

if [[ "$BASE_PATH" == "" || "$NAME" == "" || "$POLICY" == "" ]]; then
  echo "ERROR: requring directory, name of VM and policy"
  exit 1
fi

cat "$BASE_PATH/godh.cert" | base64 >"$BASE_PATH/godh.cert.base64"
cat "$BASE_PATH/launch_blob.bin" | base64 >"$BASE_PATH/launch_blob.bin.base64"

# qemu is peculiar about paths so lets define them properly
OVMF=$(realpath "$BASE_PATH/OVMF.fd")
IMAGE=$(realpath "$BASE_PATH/debian.qcow2")
GODH=$(realpath "$BASE_PATH/godh.cert.base64")
LAUNCH_BLOB=$(realpath "$BASE_PATH/launch_blob.bin.base64")
QMP_SOCK=$(realpath "$BASE_PATH/qmp_sock")

# remove old socket
rm -f "$QMP_SOCK"

echo "Starting VM"
"$QEMU" \
  -name "$NAME",process="$NAME" \
  -enable-kvm \
  -cpu EPYC \
  -machine q35,vmport=off \
  -machine memory-encryption=sev0 \
  -m 2G \
  -drive if=pflash,format=raw,unit=0,file="$OVMF",readonly=on \
  -drive file="$IMAGE",format=qcow2 \
  -object sev-guest,id=sev0,cbitpos=47,reduced-phys-bits=1,policy="$POLICY",dh-cert-file="$GODH",session-file="$LAUNCH_BLOB" \
  -netdev user,id=vmnic,hostfwd=tcp::5555-:22 \
  -device e1000,netdev=vmnic \
  -nographic \
  -qmp unix:"$QMP_SOCK",server,nowait \
  -serial mon:telnet:127.0.0.1:6666,server,nowait \
  -S 2>&1 >/dev/null &
