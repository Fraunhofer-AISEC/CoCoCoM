# Migration of Operating System Containers in Encrypted Virtual Machines

This repository is not actively maintained and has been published as part of the conference workshop CCSW'21.

> Joana Pecholt, Monika Huber, and Sascha Wessel. 2021. Live Migration of Operating System Containers in Encrypted Virtual Machines. Proceedings of the 2021 on Cloud Computing Security Workshop. Association for Computing Machinery, New York, NY, USA, 125–137. DOI:<https://doi.org/10.1145/3474123.3486761>

Note that SEV and SEV-ES lack several required features for confidentiality and integrity protection and have several known vulnerablities. Thus, looking at AMD SEV-SNP, Intel TDX or Arm CCA is recommended.

## Introduction

This is a collection of scripts to live-migrate containers in encrypted virtual machines. This repository is split into four parts that address different aspects.

* The host setup ([host-setup](host-setup/Readme.md))
* The launch of an SEV-encrypted VM with secret injection for full disk encryption ([injection](injection/Readme.md)).
* The migration of an SEV-encrypted VM ([migration](migration/Readme.md))
* The VM / network setup with wireguard that allows transparent migration of containers ([VM-setup](VM-setup/Readme.md))

## Compatibility

This guide is based on the setup of an Ubuntu 20.04 server running on an EPYC Naples chip and AMD firmware version API:0.17 build:22. This guide does not cover SEV-ES or SEV-SNP, only SEV which is the first generation of AMD's technology.

Below are the versions of the main components that are used. SEV secret injection and SEV-VM migration were developped in different repositories and/or branches at the point of implementation.

| Component                 | Injection                                                                                                                      | Migration                                                                                                                      |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| Guest Kernel              | see host kernel                                                                                                                | see host kernel                                                                                                                |
| Guest VM Debian Installer | debian-11.2.0-a net installer for amd64                                                                                        | debian-11.2.0-a net installer for amd64                                                                                        |
| OVMF                      | [tianocore/edk2 branch:master](https://github.com/tianocore/edk2/), commit:3b769c5110                                          | [AMDESE/ovmf branch:sev-migration-v1](https://github.com/AMDESE/ovmf/tree/sev-migration-v1), commit:89c0166a5e                 |
| QEMU                      | QEMU 6.0.0, [Qemu/qemu](https://github.com/qemu/qemu/), tag:v6.0.0                                                             | QEMU 5.0.50, [AMDESE/qemu, branch:sev-migration-v1](https://github.com/AMDESE/qemu/tree/sev-migration-v1), commit:6d613bbf56   |
| Host kernel               | Linux 5.7, [AMDESE/linux, branch:sev-migration-v8](https://github.com/AMDESE/linux/tree/sev-migration-v8), commit:a70e7ea40c47 | Linux 5.7, [AMDESE/linux, branch:sev-migration-v8](https://github.com/AMDESE/linux/tree/sev-migration-v8), commit:a70e7ea40c47 |
