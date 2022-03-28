
# Host Setup

In the following, we prepare the host machine, which requires its UEFI, kernel, host system and VM manager (QEMU) to be configured so that SEV is supported and SEV secret injections and SEV-VM migrations are possible.

## UEFI

The UEFI must be configured to support SEV. Depending on the system, it may be required to additionally disable SEV-ES. This includes the following setting which typically looks similar to this: \
`Advanced>CPU Configuration>SEV-ES ASID Space Limit = 1` \
 (Here, value 1 disables SEV-ES, 2 means 1 SEV-ES VM, 4 means 3 and so forth)

## Kernel, QEMU, OVMF and SEV-Tool

The `build_components.sh` script builds [QEMU](https://github.com/qemu/qemu/), AMD's forked [Linux kernel](https://github.com/AMDESE/linux), [OVMF](https://github.com/AMDESE/ovmf/) and [QEMU](https://github.com/AMDESE/qemu/) as well as AMD's [sev-tool](https://github.com/AMDESE/sev-tool/). By running the `install.sh` script, the sev-tool and kernel are installed and grub is configured to boot said kernel by default.

```sh
# install dependencies
sudo apt-get install -y --no-install-recommends git bc build-essential libncurses-dev flex bison openssl libssl-dev dkms libelf-dev libudev-dev libpci-dev libiberty-dev autoconf dwarves libpixman-1-dev libglib2.0-dev binutils-dev pkg-config ninja-build make gcc g++ automake wget uuid-dev libvirt-dev netcat-bsd

sudo usermod -aG kvm $USER

./build_components.sh

# IMPORTANT - this installs a custom kernel
sudo ./install.sh

# check for successful configuration (grub / boot) first!
reboot
```

## Host setup Check

Host support for SEV-encrypted VMs can be verified as follows.

```sh
$ sudo dmesg | grep -i SEV
...
[   17.397396] ccp 0000:05:00.2: sev enabled
[   17.415455] ccp 0000:05:00.2: SEV firmware update successful
[   17.437978] ccp 0000:05:00.2: SEV API:0.17 build:22
...
```

## Guest Setup and Deployment

At the point of implementation, both SEV launch injection features and SEV migration were developped in separate branches for each of the required components. As a result, it is not possible to use both features at the same time.

See the respective REAMEs under [injection](injection/Readme.md) and [migration](migration/Readme.md) for more information and guidelines.
