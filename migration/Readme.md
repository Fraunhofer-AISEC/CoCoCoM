# Setup for SEV-VM Migration

The following guide describes how to get a server to run encrypted Virtual Machines and migrate these using the first generation of AMD SEV technology. \
"Host" means the system which will launch or receive SEV-encrypted VMs, while "guest" refers to the VMs. Destination is the host that receives an SEV-VM, while the source refers to the host sending it.

## Guest VM

In the following, we detail how a VM can be created to be used with SEV migration.

* The newly created disk will look as follows:

```
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sda      8:0    0   16G  0 disk
|-sda1   8:1    0  512M  0 part /boot/efi
|-sda2   8:2    0 14.5G  0 part /
`-sda3   8:3    0  976M  0 part [SWAP]
```

### OVMF Build

* To migrate SEV-VMs, special support in the OVMF is required. We move the previously built OVMF to the desired directory. It consists of  `OVMF_CODE.fd` and `OVMF_VARS.fd` in separate files.

```sh
# ADAPT destination
cp ../build/migration/OVMF* /<path>/<to>/<VM-images>/
```

### Full Debian VM Installation

* An ISO file for a debian OS is required, e.g., a [debian net installer](https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.2.0-amd64-netinst.iso)
* The below commands are used to install a VM with EFI support. The installation is performed without enabling SEV.

```sh
# on host
./build/migration/qemu/qemu-img create -f qcow2 debian.qcow2 16G
# We added port 5555 from host to be forwarded to VM port 22 (ssh)
# tip: -k de sets the keyboard layout (German in this example)
# ADAPT HERE path of iso
./build/migration/qemu/x86_64-softmmu/qemu-system-x86_64 \
  -cdrom </path/to/debian iso> \
  -enable-kvm \
  -m 2G \
  -netdev user,id=net0,hostfwd=tcp::5555-:22 \
  -device e1000,netdev=net0 \
  -drive file=debian.qcow2,format=qcow2 \
  -drive if=pflash,format=raw,unit=0,file=OVMF_CODE.fd,readonly=on \
  -drive if=pflash,format=raw,unit=1,file=OVMF_VARS.fd
```

* For ease of use no FDE (full disk encryption) is used. The VM is then rebooted
* Transfer `injection/vm-scripts/install-kernel.sh` and the kernel are to the VM, e.g., via ssh/scp:

```sh
# On host
# ADAPT HERE to correct paths where files resides
# ADAPT HERE to correct username
scp -P 5555 -o PubkeyAuthentication=no -r /path/to/repo/build/migration/kernel/linux-image* /path/to/repo/injection/vm-scripts/install_kernel.sh  <user>@localhost:
```

* The custom kernel inside of the VM is installed as follows:

```sh
# in VM
sudo ./install_kernel.sh ./linux-image*
reboot
```

* The VM can now be booted with SEV using a conventional OVMF image supporting SEV

### Installation of Container Runtime, VPN / wireguard

For this, follow the respective [setup guide](../VM-setup/Readme.md).

### Local VM Start:

* To locally deploy an SEV-VM (without secret injection), a directory containing the VM image (`debian.qcow2`) as well as OVMF image (`OVMF_CODE.fd`) and variables (`OVMF_VARS.fd`) is required
* Run:

```sh
# On host
# ADAPT path
./host-scripts/migration-VM.sh run \
  --name my-vm \
  --policy 0 \
  --source-directory </path/to/images/>
```

* The QEMU stdio can be accessed over telnet at all times and the VM via ssh once the VM's sshd  is running:

```sh
# On host
telnet localhost 6666
# On host
ssh -p 5555 <user>@localhost
```

* It is possible that the boot prematurely ends in the UEFI shell (after "freezing" for up to one minute). To fix this long-term, the OVMF Variables (OVMF_VARS.fd) must be configured appropriately.

```sh
# in UEFI Shell
# ADAPT paths - They might differ
# Tab-completion should work after the disk is selected

# Option 1: manually run
Shell> FS0:EFI\debian\grubx64.efi

# Option 2: Long-term fix: changes boot configuration
# (modifies OVMF_VARS.fd)
Shell> bcfg boot add 0 FS0:EFI\debian\grubx64.efi my-boot
# reboot
```

### Check for SEV migration support

The below command shows if SEV is active and live migration is enabled.

```sh
# in VM
$ sudo dmesg | grep -i sev
...
[    0.022517] SEV is active, SWIOTLB default size set to 256MB
[    0.103718] AMD Secure Encrypted Virtualization (SEV) active
[    0.855435] setup_kvm_sev_migration: live migration enabled in OVMF
...
```

### Migration:

* The destination must have the repository and completed the host setup as well
* In our experience, the destination machine must have had an SEV-VM running, either currently or previously, in order for the migration to suceed
* The source must be able to connect to the destination via ssh (no password prompt) using the provided user name
* See the known issues [below](#known-issues)
* The destination must be prepared: `OVMF_*` and VM images from the source must be transferred to a dedicated directory on the destination. The files must be named `debian.qcow2`,  `OVMF_CODE.fd` and `OVMF_VARS.fd`.
* Migrate the running SEV-VM: (or check help messages)

```sh
# On host, source machine
# ADAPT paths, username, target and password
./host-scripts/migration-VM.sh migrate \
  --name my-vm \
  --policy 0 \
  --user <ssh username to remote host> \
  --dest-directory </destination/path/to/dir/with/images> \
  --source-directory </source/path/to/dir/with/images> \
  --target <servername> \
  --port 4444 \
  --remote-git </path/to/repo/on/remote/machine>
```

* If the dirty-page-rate is too high, the maximum downtime will have to be extended (default is 1sec) so that the migration will not hang in the pre-copy state indefinetly. It may be necessary to increase it to several minutes depending on the processes running inside the VM.

```sh
# On host, Source machine
# ADAPT the downtime (in seconds) and path
./change-downtime.sh <seconds> -s </path/to/dir/with/images>
```

* __Note:__ The countdown will freeze as soon as the pre-copy phase is complete and the downtime phase of the migration commences, continuously showing the same remaining time. This should not last longer than the shown time, and the script will continue after completing the downtime phase.
* The notes under `injection/injection.md` they contain further information, e.g., on how to query QMP
