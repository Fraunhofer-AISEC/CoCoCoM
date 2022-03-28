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

# Description: This script prepares for an incoming SEV-encrypted VM on this
# machine.

set -e

ARK_FILE="ark.cert"
ASK_FILE="ask.cert"
OCA_FILE="oca.cert"
CEK_FILE="cek.cert"
PEK_FILE="pek.cert"
PDH_FILE="pdh.cert"

SOURCE_DIR=$(dirname "$0")
QEMU="$(git -C "$SOURCE_DIR" rev-parse --show-toplevel)/build/migration/qemu/x86_64-softmmu/qemu-system-x86_64"

while test $# -gt 0; do
  case "$1" in
  -h | --help)
    echo "Tool to receive incoming SEV-encrypted VMs."
    echo " "
    echo "Run with: ./launch.sh [-f, --flag <value>]"
    echo "-h, --help                         Show this help"
    echo "-d, --directory </path/to/dir>     Directory in which to VM image and OVMF are located (locally)"
    echo "-n, --name <vm-name>               Name of VM to be launched"
    echo "-p, --port <port>                  Port through which the VM will be received"
    echo "Note: SEV Guest Policy and source PDH are set during migration by source QEMU instance and do not need to be provided separately"
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
  -n | --name)
    shift
    NAME="$1"
    vm_pid=$(pgrep "$NAME" || true)
    if [[ "$vm_pid" != "" ]]; then
      echo "ERROR: VM with name $name already running."
      exit 1
    fi
    shift
    ;;
  -p | --port)
    shift
    PORT="$1"
    re='^[0-9]+$'
    if ! [[ "$PORT" =~ $re ]]; then
      echo "ERROR: Port is not a number."
      exit 1
    fi
    shift
    ;;
  *)
    echo "Detected unnecessary argument? ($1)"
    exit 1
    ;;
  esac
done

if [[ "$PORT" == "" || "$BASE_PATH" == "" || "$NAME" == "" ]]; then
  echo "ERROR: Missing required information (port, PDH, path and VM name required)."
  exit 1
fi

# qemu is peculiar about paths so lets define them properly
IMAGE=$(realpath "$BASE_PATH/debian.qcow2")
OVMF=$(realpath "$BASE_PATH/OVMF_CODE.fd")
OVMF_VARS=$(realpath "$BASE_PATH/OVMF_VARS.fd")
QMP_SOCK=$(realpath "$BASE_PATH/qmp_sock")


# run
# remove old socket
rm -f "$QMP_SOCK"
echo "[STATUS] Preparing for incoming VM on destination..."
nohup "$QEMU" \
  -name "$NAME",process="$NAME" \
  -enable-kvm \
  -cpu EPYC \
  -machine q35,vmport=off \
  -machine memory-encryption=sev0 \
  -object sev-guest,id=sev0,cbitpos=47,reduced-phys-bits=1 \
  -m 2G \
  -drive if=pflash,format=raw,unit=0,file="$OVMF",readonly=on \
  -drive if=pflash,format=raw,unit=1,file="$OVMF_VARS" \
  -drive file="$IMAGE",format=qcow2 \
  -netdev user,id=vmnic,hostfwd=tcp::5555-:22 \
  -device e1000,netdev=vmnic \
  -nographic \
  -qmp unix:"$QMP_SOCK",server,nowait \
  -serial mon:telnet:127.0.0.1:6666,server,nowait \
  -incoming tcp:0:"$PORT" </dev/null &>/dev/null &


# await_socket
count=0
while true; do
  if [ ! -S "$QMP_SOCK" ]; then
    if [[ "$count" == 30 ]]; then
      echo "ERROR: no socket found?"
      exit 1
    fi
  else
    test=$( (
      echo
      sleep .01
      echo '{ "execute": "qmp_capabilities" }'
      sleep .1
    ) | nc -U "$QMP_SOCK" -N | grep "return" | wc -l)
    if [[ "$test" > 0 ]]; then
      break
    fi
    if [[ "$count" == 30 ]]; then
      echo "ERROR: socket brocken?"
      exit 1
    fi
  fi
  let count=count+1
  sleep .1
done


#set_migration_params
data=$( (
  echo
  sleep .01
  echo '{ "execute": "qmp_capabilities" }'
  sleep .01
  echo '{ "execute": "migrate-set-parameters" ,
"arguments": { "max-bandwidth": 10000000000 }'
  sleep .01
) | nc -U "$QMP_SOCK" -N)
if [[ $(echo "$data" | grep error | wc -l) != 0 ]]; then
  echo "ERROR: failed to set migration parameters?"
  exit 1
fi


echo "Migration prepared."
