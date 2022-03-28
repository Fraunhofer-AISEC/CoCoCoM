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

# Description: This script deploys local SEV-encrypted VMs (no injection)
# on this machine and migrates these to a specified destination.

set -e

SOURCE_DIR=$(dirname "$0")
BASE_PATH=$(git -C "$SOURCE_DIR" rev-parse --show-toplevel)/build
QEMU="$BASE_PATH/migration/qemu/x86_64-softmmu/qemu-system-x86_64"
SEVTOOL="$BASE_PATH/sev-tool/src/sevtool"

RECEIVE_SCRIPT="receive.sh"
CERTS_EXPORT_FILE="certs_export.zip"
ARK_FILE="ark.cert"
ASK_FILE="ask.cert"
OCA_FILE="oca.cert"
CEK_FILE="cek.cert"
PEK_FILE="pek.cert"
PDH_FILE="pdh.cert"

USER=""

IMAGE_FILE="debian.qcow2"
OVMF_FILE="OVMF_CODE.fd"
OVMF_VARS_FILE="OVMF_VARS.fd"
QMP_SOCK_FILE="qmp_sock"

#returns pid if running
vm_pid() {
  # allow this command to fail (-> || true) if no pid found
  VM_PID=$(pgrep "$NAME") || true
}

validate_cert_chain() {
  ssh "$USER@$TARGET" -C "mkdir -p $TARGET_PATH/target; $REMOTE_SEVTOOL --ofolder $TARGET_PATH/target --export_cert_chain"
  mkdir -p "$SOURCE_PATH/target"
  rsync -a "$USER@$TARGET:$TARGET_PATH/target/$CERTS_EXPORT_FILE" "$SOURCE_PATH/target"
  unzip -o "$SOURCE_PATH/target/$CERTS_EXPORT_FILE" -d "$SOURCE_PATH/target"
  if [ $("$SEVTOOL" --ofolder "$SOURCE_PATH/target" --validate_cert_chain | grep -i success | wc -l) == 0 ]; then
    echo "Failed certificate chain validation."
    exit 1
  fi
}

print_help() {
  echo "Tool to start SEV-encrypted VMs on a remote host."
  echo " "
  echo "Run with: ./migration-VM.sh <command> [-f, --flag <value>]"
  echo " "
  echo "options:"
  echo "run                                    Runs a VM - This will block the terminal with the VM"
  echo "migrate                                Migrates the specified VM to the specified destination"
  echo "kill                                   Show this help"
  echo "-h, --help                                Show this help"
  echo "-s, --source-directory </path/to/dir>     Directory in which to operate on source (locally)"
  echo "-d, --dest-directory </path/to/dir>       Directory in which to operate on Target/dest"
  echo "-n, --name <VM-name>                      Name of the VM (must be unique on the host)"
  echo "-t, --target <name/IP>                    Target/Destination where to send VM to"
  echo "-o, --policy <policy>                     Guest Policy for SEV-VM"
  echo "-p, --port <port>                         VM will be launched as incoming VM (arriving over specified port)"
  echo "-u, --user <username>                     User name to be used for ssh connection (preferably works with private key authentication)."
  echo "-g, --remote-git <dir>                    Path to git repository on remote machine"
}

run() {
  rm -f "$QMP_SOCK"
  echo "Starting VM"
  sh -c "$QEMU \
        -name $NAME,process=$NAME \
        -enable-kvm \
        -cpu EPYC \
        -machine q35,vmport=off \
        -machine memory-encryption=sev0 \
        -object sev-guest,id=sev0,cbitpos=47,reduced-phys-bits=1,policy=$POLICY \
        -m 2G \
        -drive if=pflash,format=raw,unit=0,file=$OVMF,readonly=on \
        -drive if=pflash,format=raw,unit=1,file=$OVMF_VARS \
        -drive file=$IMAGE,format=qcow2 \
        -netdev user,id=vmnic,hostfwd=tcp::5555-:22 \
        -device e1000,netdev=vmnic \
        -nographic \
        -qmp unix:$QMP_SOCK,server,nowait \
        -serial mon:telnet:127.0.0.1:6666,server,nowait 2>&1 >/dev/null &"
}

set_migration_params() {
  #get params
  ASK_ARK_CERTS=$(cat "$SOURCE_PATH/target/$ASK_FILE" "$SOURCE_PATH/target/$ARK_FILE" | base64 | tr -d '\n')
  PLAT_CERTS=$(cat "$SOURCE_PATH/target/$PEK_FILE" "$SOURCE_PATH/target/$OCA_FILE" "$SOURCE_PATH/target/$CEK_FILE" | base64 | tr -d '\n')
  # target pdh
  PDH_CERT=$(cat "$SOURCE_PATH/target/$PDH_FILE" | base64 | tr -d '\n')
  if [[ "$ASK_ARK_CERTS" == "" || "$PLAT_CERTS" == "" || "$PDH_CERT" == "" ]]; then
    echo "ERROR: Could not find required certificates?"
    exit 1
  fi
  #set params
  data=$( (
    echo
    sleep .01
    echo '{ "execute": "qmp_capabilities" }'
    sleep .01
    echo '{ "execute": "migrate-set-parameters" ,
  "arguments": { "max-bandwidth": 10000000000,
  "sev-pdh": "'$PDH_CERT'",
  "sev-plat-cert": "'$PLAT_CERTS'",
  "sev-amd-cert": "'$ASK_ARK_CERTS'" } }'
    sleep .01
  ) | nc -U "$QMP_SOCK" -N)
  if [[ $(echo "$data" | grep error | wc -l) != 0 ]]; then
    echo "ERROR: failed to set migration parameters?"
    exit 1
  fi
  echo "[STATUS] Local parameters set"
}

# Note: certificates / policy required by target are provided by the source
# QEMU instance during migration
prepare_remote() {
  ssh "$USER@$TARGET" "$REMOTE_SCRIPT_DIR/$RECEIVE_SCRIPT -d $TARGET_PATH -p $PORT -n $NAME"
  echo "[STATUS] Incoming VM prepared on target."
}

migrate() {
  echo "[STATUS] Starting migration....."
  # instead of copying incremental disk changes (inc), block (blk), meaning full disk copy can be set to true
  # default is false
  data=$( (
    echo
    sleep .01
    echo '{ "execute": "qmp_capabilities" }'
    sleep .01
    echo '{ "execute": "migrate", "arguments": { "uri":
"tcp:'$TARGET':'$PORT'"} }'
    sleep .01
  ) | nc -U $QMP_SOCK -N)
  if [[ $(echo "$data" | grep error | wc -l) != 0 ]]; then
    echo "ERROR: failed to start migration"
    exit 1
  fi
}

await_completion() {
  count=0
  echo -n "Minimal remaining migration time (does not account for dirty pages): "
  while true; do
    test=$( (
      echo
      sleep .01
      echo '{ "execute": "qmp_capabilities" }'
      sleep .01
      echo '{ "execute": "query-migrate" }'
      sleep .01
    ) | nc -U "$QMP_SOCK" -N 2>&1)
    if [[ $(echo "$test" | grep "failed" | wc -l) != 0 ]]; then
      echo -e "\nERROR: Failed migration. The VM will most likely be unusable at this point."
      exit 1
    fi
    if [[ $(echo "$test" | grep "completed" | wc -l) != 0 ]]; then
      echo -e "\n[STATUS] Finished Migration."
      break
    fi
    if [[ $((count % 10)) == 0 ]]; then #pings roughly every 1 - 1.1 sec
      # remaining is in bytes
      remaining=$(echo "$test" | tail -n1 | sed -e 's/.*"remaining": \([0-9]\+\),.*/\1/')
      # Mbit per seconds
      mbps=$(echo "$test" | tail -n1 | sed -e 's/.*"mbps": \([0-9.]\+\),.*/\1/')
      if [[ "$mbps" != "0" && "$mbps" != "" ]]; then
        mins=$(echo "print(int($remaining*8/($mbps*1024*1024)/60))" | python3)
        secs=$(echo "print(int($remaining*8/($mbps*1024*1024)-int($remaining*8/($mbps*1024*1024)/60)*60))" | python3)
        echo -n -e "\\rMinimal remaining migration time (does not account for dirty pages): $mins minutes and $secs seconds"
      fi
    fi
    let count=count+1
    sleep .1
  done
}


# -----------------------------------------------------------------
if [[ $# == 0 ]]; then
  print_help
  exit 0
fi
while test $# -gt 0; do
  case "$1" in
  -h | --help)
    print_help
    exit 0
    ;;
  run)
    shift
    COMMAND=run
    ;;
  migrate)
    shift
    COMMAND=migrate
    ;;
  kill)
    shift
    COMMAND=kill
    ;;
  -n | --name)
    shift
    NAME="${1%/}"
    shift
    ;;
  -s | --source-directory)
    shift
    SOURCE_PATH="${1%/}"
    shift
    ;;
  -d | --dest-directory)
    shift
    TARGET_PATH="${1%/}"
    shift
    ;;
  -p | --port)
    shift
    PORT="$1"
    shift
    re='^[0-9]+$'
    if ! [[ "$PORT" =~ $re ]]; then
      echo "ERROR: port must be a number."
      exit 1
    fi
    ;;
  -o | --policy)
    shift
    POLICY="$1"
    shift
    # hex or base10 encoded
    re='^(0x)*[0-9]+$'
    if ! [[ "$POLICY" =~ $re ]]; then
      echo "ERROR: POLICY must be a number."
      exit 1
    fi
    ;;
  -t | --target)
    shift
    TARGET="$1"
    shift
    ;;
  -u | --user)
    shift
    USER=$1
    shift
    ;;
  -g | --remote-git)
    shift
    REMOTE_BASE="$1"
    shift
    ;;
  *)
    echo "Detected unknown or not-yet-implemented command or unnecessary argument? ($1)"
    exit 1
    ;;
  esac
done


if [[ "$SOURCE_PATH" == "" ]]; then
  echo "Specify source directory containing the images."
  exit 1
fi

IMAGE=$(realpath "$SOURCE_PATH/$IMAGE_FILE")
OVMF=$(realpath "$SOURCE_PATH/$OVMF_FILE")
OVMF_VARS=$(realpath "$SOURCE_PATH/$OVMF_VARS_FILE")
QMP_SOCK=$(realpath "$SOURCE_PATH/$QMP_SOCK_FILE")

case "$COMMAND" in
run)
  if [[ "$NAME" == "" || $POLICY == "" ]]; then
    echo "ERROR: Launch requires VM name and launch policy."
    exit 1
  fi
  vm_pid
  if [[ "$VM_PID" != "" ]]; then
    echo "ERROR: VM with name $NAME already running. Kill first."
    exit 1
  fi
  run
  ;;
migrate)

  if [[ "$REMOTE_BASE" == "" ]]; then
    echo "ERROR: location of this git repository on the remote machine not specified."
    exit 1
  fi
  REMOTE_SCRIPT_DIR="$REMOTE_BASE/migration/host-scripts"
  REMOTE_SEVTOOL="$REMOTE_BASE/build/sev-tool/src/sevtool"
  if [[ "$NAME" == "" || "$TARGET" == "" || "$TARGET_PATH" == "" || "$PORT" == "" || "$USER" == "" ]]; then
    echo "ERROR: Migration requires VM name, target, destination dir username (for ssh connection), and destination port."
    exit 1
  fi
  vm_pid
  if [[ "$VM_PID" == "" ]]; then
    echo "ERROR:  No running VM with name $NAME found."
    exit 1
  fi
  if [[ $(ssh "$USER@$TARGET" -C "pgrep $NAME" | wc -l) != 0 ]]; then
    echo "ERROR: VM with same name already running on destination?"
    exit 1
  fi
  validate_cert_chain
  set_migration_params
  prepare_remote
  migrate
  await_completion
  echo "[STATUS] Migration complete."
  echo "Make sure to kill the VM on the source platform, it is unusable at this point."
  ;;
kill)
  vm_pid
  if [[ "$VM_PID" == "" ]]; then
    echo "ERROR: No VM instance with name $NAME running."
    exit 1
  fi
  if [[ $(echo "$VM_PID" | grep ' ' | wc -l) > 0 ]]; then
    echo "ERROR: Multiple instances running. Kill manually"
    exit 1
  fi
  echo "[STATUS] Killing VM..."
  kill "$VM_PID"
  ;;
*)
  echo "ERROR: Unimplemented command or parameter: $1"
  exit 1
  ;;
esac
