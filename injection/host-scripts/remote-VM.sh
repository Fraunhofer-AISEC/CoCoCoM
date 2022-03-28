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

# Description: This script allows to run SEV-encrypted VMs on a remote
# machine. This includes the authentication of the machine, verification of
# launch measures and injection of secrets.

set -e

# Default vars
PO_PATH=" ~/" # at destination
NAME="my-vm"  # default name of process
GO_PATH="."   # current dir is default
USER=""       # no default user

OVMF_FILE="OVMF.fd"
IMAGE_FILE="debian.qcow2"
SECRET_FILE="secret.txt"
GODH_FILE="godh.cert"
PEK_FILE="pek.cert"
TK_FILE="tmp_tk.bin"
PACKAGED_SECRET_HEADER_FILE="packaged_secret_header.bin"
PACKAGED_SECRET_FILE="packaged_secret.bin"
CERTS_EXPORT_FILE="certs_export.zip"
POLICY_FILE="policy.hex"
BUILD_FILE="build.hex"
CALC_MEASUREMENT_FILE="calc_measurement_out.txt"
LAUNCH_BLOB_FILE="launch_blob.bin"
LAUNCH_MEASURE_FILE="launch_measure.bin"

LAUNCH_SCRIPT="launch.sh"
GET_MEASURE_SCRIPT="get_measure.sh"
CREATE_SECRET_SCRIPT="create_secret.py"
INJECT_SCRIPT="inject.sh"
CONTINUE_SCRIPT="continue.sh"

# Directory where this script is located (and thus the py script)
SCRIPT_DIR=$(realpath $(dirname "$0}"))

BASE_PATH=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)/build
SEVTOOL="$BASE_PATH/sev-tool/src/sevtool"


#returns pid if running
vm_pid() {
  # allow this command to fail (-> || true) if no pid found
  VM_PID=$(ssh "$USER@$DEST" "pgrep $NAME" || true)
}

transfer() {
  rsync -a "$@" "$USER@$DEST":"$PO_PATH" >/dev/null
}

get() {
  scp "$USER@$DEST":"$PO_PATH/$1" "$GO_PATH" >/dev/null
}

get_build() {
  echo "[STATUS] Obtaining Platform build ..."
  # Assumes symlink to sevtool on remote machine
  build=$(ssh "$USER@$DEST" $REMOTE_SEVTOOL --platform_status | grep build | awk '{print $2}')
  printf "%x\n" "$build" >"$GO_PATH/$BUILD_FILE"
}

validate_cert_chain() {
  echo "[STATUS] Validating cert chain ..."
  # obtain certs on remote machine
  ssh "$USER@$DEST" -C "$REMOTE_SEVTOOL --ofolder $PO_PATH --export_cert_chain > /dev/null"
  get certs_export.zip
  unzip -o "$GO_PATH/$CERTS_EXPORT_FILE" -d "$GO_PATH" >/dev/null
  if [ $("$SEVTOOL" --ofolder "$GO_PATH" --validate_cert_chain | grep -i success | wc -l) == 0 ]; then
    echo "Failed certificate chain validation."
    exit 1
  fi
}

launch() {
  echo "[STATUS] Launching VM ..."
  "$SEVTOOL" --ofolder "$GO_PATH" --generate_launch_blob "$POLICY" >/dev/null
  echo "$POLICY" >"$POLICY_FILE"
  transfer "$GO_PATH/$LAUNCH_BLOB_FILE" "$GO_PATH/$GODH_FILE" # $GO_PATH/$OVMF_FILE
  ssh "$USER@$DEST" -C "sh -c '$REMOTE_SCRIPT_DIR/$LAUNCH_SCRIPT -d $PO_PATH -o $POLICY -n $NAME > /dev/null 2>&1 &';"
  # we have to wait since it's now running detached in the background so we don't get information
  count=0
  while [[ "$count" < 30 ]]; do
    vm_pid
    if [[ "$VM_PID" != "" ]]; then
      return
    fi
    let count="$count"+1
  done
  echo "ERROR: could not detect qemu instance."
  exit 1
}

verify_measure() {
  echo "[STATUS] Validating launch measure ..."
  ssh "$USER"@"$DEST" "$REMOTE_SCRIPT_DIR/$GET_MEASURE_SCRIPT $PO_PATH"
  get "$LAUNCH_MEASURE_FILE"
  measure=$(cat "$GO_PATH/$LAUNCH_MEASURE_FILE" | xxd -p -s 0 -l 32 | tr -d '\n')
  mnonce=$(cat "$GO_PATH/$LAUNCH_MEASURE_FILE" | xxd -p -s 32 | tr -d '\n')
  build=$(cat "$GO_PATH/$BUILD_FILE")
  context=04
  # Obtain API from received pek cert
  api=$(dd if="$GO_PATH/$PEK_FILE" ibs=1 skip=4 count=2 2>/dev/null | xxd -p)
  api_major=$(echo "$api" | cut -c1-2)
  api_minor=$(echo "$api" | cut -c3-4)
  # This is for Naples only - Rome must be adapted to sha384
  digest=$(sha256sum "$GO_PATH/$OVMF_FILE" | awk '{print $1;}')
  tik=$(xxd -p "$GO_PATH/$TK_FILE" | tr -d '\n' | tail -c 32)
  if [[ "$POLICY" == "" ]]; then
    if [ ! -f "$GO_PATH/$POLICY_FILE" ]; then
      echo "ERROR: no policy specified and no policy file found."
      exit 1
    fi
    POLICY=$(cat "$GO_PATH/$POLICY_FILE")
  fi
  "$SEVTOOL" --ofolder "$GO_PATH" --calc_measurement "$context" "$api_major" "$api_minor" "$build" "$POLICY" "$digest" "$mnonce" "$tik" >/dev/null
  if [[ "$(cat $GO_PATH/$CALC_MEASUREMENT_FILE)" == $measure ]]; then
    echo "> Measurement matches."
  else
    echo "Failed check"
    echo "Reported measure: $measure"
    echo "Calculated measure: $(cat $GO_PATH/$CALC_MEASUREMENT_FILE)"
    exit 1
  fi

}

inject_secret() {
  echo "[STATUS] Injecting launch secret ..."
  if [ "$(which python3)" == "" ]; then
    echo "[ERROR] Missing python3 to run script for secret packaging."
    exit 1
  fi
  "$SCRIPT_DIR/$CREATE_SECRET_SCRIPT" "$PW" "$GO_PATH/$SECRET_FILE"
  "$SEVTOOL" --ofolder "$GO_PATH" --package_secret >/dev/null
  transfer "$GO_PATH/$PACKAGED_SECRET_FILE" "$GO_PATH/$PACKAGED_SECRET_HEADER_FILE"
  ssh "$USER@$DEST" "$REMOTE_SCRIPT_DIR/$INJECT_SCRIPT $PO_PATH"
}

continue() {
  echo "[STATUS] Continuing VM..."
  ssh $USER@$DEST "$REMOTE_SCRIPT_DIR/$CONTINUE_SCRIPT $PO_PATH"
}

run() {
  get_build
  validate_cert_chain
  launch
  verify_measure
  inject_secret
  continue
}


#-----------------------------------------------------------------------------
# Arguments retrieval
if [[ "$#" == 0 ]]; then
  echo "Use flag --help or -h for information."
  exit 0
fi

while test $# -gt 0; do
  case "$1" in
  -h | --help)
    echo "Tool to start SEV-encrypted VMs on a remote host."
    echo " "
    echo "Run with: ./remote-VM.sh <command> -t <Ip> [-f,--flag <value>]"
    echo " "
    echo "commands:"
    echo "get_build                 Obtains information on platform build (required for measure verification)"
    echo "validate_cert_chain       Obtains certificate chain from server and verifies it"
    echo "launch                    Launches VM with given policy."
    echo "verify_measure            Verifies the measure of the launched VM"
    echo "inject_secret             Injects the given disk encryption password into the VM"
    echo "continue                  Continues the VM (e.g. after injection)"
    echo "run                       Performs all of the specified steps above to start a VM"
    echo "kill                      Kills the VM on the server"
    echo "-h, --help                show this help"
    echo "-t, --target <ip/host>          Target host capable of AMD SEV, ssh-connection"
    echo "-s, --source-directory <dir>    Directory in which to operate on GO (locally)"
    echo "-d, --dest-directory <dir>      Directory in which to operate on PO (remotely)"
    echo "-n, --name <VM name>            Name of the VM (must be unique on the PO)"
    echo "-o, --policy <int>              Policy to be used for VM launch (eg 0)."
    echo "-p, --password <pw>             Disk encryption password"
    echo "-u, --user <username>           User name to be used for ssh connection (preferably works with private key authentication)."
    echo "-g, --remote-git <dir>          Path to git repository on remote machine"
    exit 0
    ;;
  get_build)
    COMMAND=get_build
    shift
    ;;
  validate_cert_chain)
    shift
    COMMAND=validate_cert_chain
    ;;
  launch)
    shift
    COMMAND=launch
    ;;
  verify_measure)
    shift
    COMMAND=verify_measure
    ;;
  inject_secret)
    shift
    COMMAND=inject_secret
    ;;
  continue)
    shift
    COMMAND=continue
    ;;
  run)
    shift
    COMMAND=run
    ;;
  kill)
    shift
    COMMAND=kill
    ;;
  -t | --target)
    shift
    DEST="$1"
    shift
    ;;
  -d | --dest-directory)
    shift
    PO_PATH="${1%/}"
    shift
    ;;
  -s | --source-directory)
    shift
    # remove trailing dash
    GO_PATH="${1%/}"
    if [ ! -d "$GO_PATH" ]; then
      echo "$GO_PATH is not an existing directory."
      exit 1
    fi
    shift
    ;;
  -o | --policy)
    shift
    POLICY="$1"
    # hex or base10 encoded
    re='^(0x)*[0-9]+$'
    if ! [[ "$POLICY" =~ $re ]]; then
      echo "Policy is not a number."
      exit 1
    fi
    shift
    ;;
  -p | --password)
    shift
    PW="$1"
    shift
    ;;
  -u | --user)
    shift
    USER="$1"
    shift
    ;;
  -n | --name)
    shift
    NAME="$1"
    shift
    ;;
  -g | --remote-git)
    shift
    REMOTE_BASE="$1"
    shift
    ;;
  *)
    echo "Detected unknown/unimplemented command or unnecessary argument? ($1)"
    exit 1
    ;;
  esac
done

if [[ "$REMOTE_BASE" == "" ]]; then
  echo "ERROR: location of this git repository on the remote machine not specified."
  exit 1
fi
REMOTE_SCRIPT_DIR="$REMOTE_BASE/injection/host-scripts"
REMOTE_SEVTOOL="$REMOTE_BASE/build/sev-tool/src/sevtool"


if [[ "$DEST" == "" ]]; then
  echo "ERROR: no destination / target specified."
  exit 1
fi

if [[ "$USER" == "" ]]; then
  echo "ERROR: no username for ssh connection specified."
  exit 1
fi

case "$COMMAND" in
get_build)
  get_build
  ;;
validate_cert_chain)
  validate_cert_chain
  ;;
launch)
  if [[ "$POLICY" == "" ]]; then
    echo "ERROR: Launch requires launch policy."
    exit 1
  fi
  if [[ $(ssh "$USER"@"$DEST" -C "pidof qemu-system-x86_64") != "" ]]; then
    echo "ERROR: VM instance already running"
    exit 1
  fi
  vm_pid
  if [[ "$VM_PID" != "" ]]; then
    echo "ERROR: VM with name $NAME already running. Kill first."
    exit 1
  fi
  launch
  ;;
verify_measure)
  vm_pid
  if [[ "$VM_PID" == "" ]]; then
    echo "ERROR: No VM with name $NAME running?"
    exit 1
  fi
  verify_measure
  ;;
inject_secret)
  if [[ "$PW" == "" ]]; then
    echo "Missing disk decryption password"
    exit 1
  fi
  vm_pid
  if [[ "$VM_PID" == "" ]]; then
    echo "ERROR: No VM with name $NAME running?"
    exit 1
  fi
  inject_secret
  ;;
continue)
  vm_pid
  if [[ "$VM_PID" == "" ]]; then
    echo "ERROR: No VM with name $NAME running?"
    exit 1
  fi
  continue
  ;;
run)
  if [[ "$POLICY" = "" || "$PW" == "" ]]; then
    echo "Missing required arguments: Specify policy and disk decryption password"
    exit 1
  fi
  vm_pid
  if [[ "$VM_PID" != "" ]]; then
    echo "ERROR: VM with name $NAME already running. Kill first."
    exit 1
  fi
  run
  ;;
kill)
  vm_pid
  if [[ "$VM_PID" == "" ]]; then
    echo "ERROR: No VM instance with name $NAME running."
    exit 1
  fi
  if [[ "$(echo $VM_PID | grep ' ' | wc -l)" > 0 ]]; then
    echo "ERROR: Multiple instances running. Kill manually"
    exit 1
  fi
  echo "[STATUS] Killing VM..."
  ssh "$USER"@"$DEST" -C "kill $VM_PID"
  ;;
*)
  echo "ERROR: Unimplemented command: $1"
  exit 1
  ;;
esac
