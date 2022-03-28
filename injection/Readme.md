# Setup for SEV with launch injection

The following guide describes how to get a server to run encrypted Virtual Machines with injection of secrets at launch using the first generation of AMD SEV technology from scratch. "Host" means the system which will launch or receive SEV-encrypted VMs, while "guest" refers to the VMs.

## Guest VM

In the following, we detail how a fully encrypted VM can be created to be used with SEV (injection).

The preparation can be split into these steps:
* First, we install debian in a VM with LUKS encryption
* Then, a second disk image is created and attached to the VM. It is then partitioned as required, all relevant data is transferred and the original boot configuration is adapted so that the second disk can boot on its own during the next boot
* Finally, the newly created disk is cleaned up and configured. The final partition looks as follows:

```
NAME               MAJ:MIN RM  SIZE RO TYPE  MOUNTPOINT
sda                  8:0    0   16G  0 disk
├─sda1               8:1    0  499M  0 part  /boot
└─sda2               8:2    0 15.5G  0 part
  └─root_crypt_dif 254:0    0 14.5G  0 crypt
    └─root_crypt   254:1    0 14.5G  0 crypt
      ├─root-root  254:2    0 13.1G  0 lvm   /
      └─root-swap  254:3    0 1024M  0 lvm   [SWAP]
```

### OVMF Build

* The fully encrypted VM requires an OVMF with integrated grub. This way, both OVMF and grub are measured during launch of the VM. The following files were built in `build_components.sh`:
  + OVMF.nosig.fd: Grub will not check for kernel / initrd signatures here
  + OVMF.sig.fd: Grub checks for kernel / initrd signatures and fails if signatures are missing or invalid

```sh
# on host
# ADAPT HERE destination
cp ../build/injection/OVMF.* /<path>/<to>/<VM-images>/
```

### Full Debian VM Installation

* An ISO file for a debian OS is required, e.g., a [debian net installer](https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.2.0-amd64-netinst.iso)
* The below commands are used to install a debian VM, EFI support is not mandatory as the corresponding files and configurations will not be transferred to the final disk. The installation is performed without enabling SEV. The Linux kernel in the ISO would have to actively enable / use SEV, which it generally does not.

```sh
# on host
./build/injection/qemu/build/qemu-img create -f qcow2 debian-temp.qcow2 16G
# We added port 5555 from host to be forwarded to VM port 22 (ssh)
# tip: -k de sets the keyboard layout (German in this example)
# ADAPT HERE path of iso
./build/injection/qemu/build/qemu-system-x86_64 \
  -cdrom </path/to/debian-iso> \
  -enable-kvm \
  -m 2G \
  -netdev user,id=net0,hostfwd=tcp::5555-:22 \
  -device e1000,netdev=net0 \
  -drive file=debian-temp.qcow2,format=qcow2
```

* The disk must be installed with full disk encryption (LUKS) enabled and rebooted
* `vm-scripts` and kernel image are transferred to the VM, e.g., via ssh/scp:

```sh
# On host
# ADAPT HERE correct paths where files resides
# ADAPT HERE correct username
scp -P 5555 -r /<path>/<to>/<repo>/build/kernel/linux-image* /<path>/<to>/<repo>/injection/vm-scripts  <user>@localhost:
```

* The custom kernel inside of the VM is installed as follows:

```sh
# in VM
sudo ./vm-scripts/install_kernel.sh ./linux-image*
reboot
```

* Remove old kernel(s)
```sh
# in VM
LINUX_BRANCH="sev-migratrion-v8"
apt-get purge -y $(dpkg -l | grep -e linux-image -e linux-header | awk '{print $2}' | grep -v "$LINUX_BRANCH")

```

### Creation of encrypted VM with AEAD

* A backup of the VM at this point is recommended
* Create a second disk and reboot the VM with the second disk attached:

```sh
# on host
# create destination disk
./build/injection/qemu/build/qemu-img create -f qcow2 debian.qcow2 16G
# start VM with both disks (and internet)
# For console-only, add: -nographic -serial mon:stdio
./build/injection/qemu/build/qemu-system-x86_64 \
  -enable-kvm \
  -m 2G \
  -drive file=debian-temp.qcow2,format=qcow2 \
  -drive file=debian.qcow2,format=qcow2 \
  -netdev user,id=vmnic,hostfwd=tcp::5555-:22 \
  -device e1000,netdev=vmnic
```

* Prepare second disk and choose a password for the encrypted root partition:

```sh
# get dependencies
sudo apt-get install gdisk lvm2 cryptsetup
# in VM
# check disk names first
lsblk
# ADAPT password
sudo ./vm-scripts/configure_aead_encryption.sh <passwd>
# Check script output for success
poweroff
```

* Boot the second disk as follows (the previously built OVMF without signature enforcement is used, see `build/ovmf/`):

```sh
# on host
# For console-only, add: -nographic -serial mon:stdio
./build/injection/qemu/build/qemu-system-x86_64 \
  -enable-kvm \
  -m 2G \
  -drive if=pflash,format=raw,unit=0,file=OVMF.nosig.fd,readonly=on \
  -drive file=debian.qcow2,format=qcow2 \
  -netdev user,id=vmnic,hostfwd=tcp::5555-:22 \
  -device e1000,netdev=vmnic
```

* Type in the password \
  __Note:__ The initramfs may show an error due to artifacts of the previous disk inside the initrd, however, after a short while the boot will continue - this will be fixed in the following \
  __Note:__ If the password is not accepted, commands described in the [optional section](Readme.md#optional) allow the boot to continue. Repeatedly press enter to end in the described shell.
* The setup is finalized as follows:

```sh
#in VM
# ADAPT password
sudo ./vm-scripts/finish_new_disk.sh <passwd>
# Ignore update-initramfs warnings and errors
# DO NOT reboot yet if kernel/initrd is to be signed
```

* __IMPORTANT:__ The newly created disk encryption key is located under `/root/root.key.backup`. To inject the key into the SEV-VM later, it must be base64 encoded. The command `finish_new_disk.sh` outputs the base64-encoded key that must be stored in a file somewhere secure (not inside VM) and must later on be used as the secret during SEV-VM launch

### Kernel and Initrd signatures

* Copy the VM kernel and initrd to the host, e.g., using ssh/scp:

```sh
# on host
# ADAPT path
mkdir </path/to/dir/>
# ADAPT username and path
scp -P 5555 <user>@localhost:/boot/* </path/to/dir/>
```

###
* Sign the files as follows:

```sh
# on host
# ADAPT to path to dir containing kernel and initrd of VM
./sign-contents.sh </path/to/dir/>
```

* Copy the signatures to the VM, e.g., using ssh/scp:

```sh
# on host
# ADAPT username and path
scp -P 5555 /<path>/<to>/<dir>/*.sig <user>@localhost:
```

* In the VM, transfer the files to the /boot directory:

```sh
# in VM
sudo mv *.sig /boot
sudo chown root:root /boot/*.sig
sudo chmod 644 /boot/*.sig
```

The VM can now be securely booted with SEV encryption enabled and SEV secret injection.

### Optional

If the VM cannot decrypt the disk, either due to errors or missing injected secret, it can still be booted. This, however, requires manual decryption of the disk in the initramfs shell (takes around half a minute until busybox shell prompt appears):

```sh
# in initramfs
# enter password (not key!)
(initramfs) cryptsetup open /dev/sda2 root_crypt
(initramfs) vgchange -ay
(initramfs) exit
# boot continues
```

### Installation of Container Runtime, VPN / wireguard

For this, see the respective [setup guide](../VM-setup/Readme.md).

## RUN VM

* If errors occur or a more detailed explanation is desired, see [injection.md](injection.md)

### Local VM Start

* To locally run a VM with launch verification and secret injection (on same machine), a directory containing the VM image (`debian.qcow2`) and OVMF image (`OVMF.fd`) as well as the base64-encoded disk encryption key is required. Run:

```sh
# On host
# ADAPT paths and password
./host-scripts/local-VM.sh run \
  --name my-vm \
  --policy 0 \
  --directory </local/path/to/dir/with/images> \
  --password <base64-encoded key>
```

* __Note:__ The VM can be reached via ssh over port 5555 and the QEMU stio via telnet over port 6666. If the VM experiences network connectivity issues, telnet can be used to check for the network configuration and interface names

### Remote VM Start

To deploy these VMs on a remote untrusted server, copy the repository to said server but exclude the secrets, namely the pgp keyring/keys and base64-encoded disk encryption key. Run `host-setup/install.sh` on the remote machine, reboot and configure its UEFI so that it enables SEV.

* The local machine must be able to connect to the destination via ssh (no password prompt) using the provided user name
* The destination directory is a directory on the remote host that contains the `debian.qcow2` and `OVMF.fd` to be run (naming must match)
* An SEV-VM is deployed as follows (see help messages of script):

```sh
# On local machine
# ADAPT paths, username, target and password
./host-scripts/remote-VM.sh run \
  --name my-vm \
  --policy 0 \
  --password <base64-encoded key of the encrypted disk> \
  --user <ssh username to remote host> \
  --dest-directory </remote/path/to/dir/with/images> \
  --source-directory </local/path/to/dir/with/OVMF> \
  --target <servername> \
  --remote-git </remote/path/to/repo>
```

### Check for active SEV

```sh
# in VM
$ sudo dmesg | grep SEV
[    0.022245] SEV is active, SWIOTLB default size set to 256MB
[    0.101850] AMD Secure Encrypted Virtualization (SEV) active
```
