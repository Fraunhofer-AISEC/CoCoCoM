# Step-by-Step Guide to inject into SEV-VMs

This document explains the steps of obtaining platform ownership, attesting an SEV-VM and injecting a secret. It also explains the QEMU/QMP commands in greater detail.

## SEV Platform Ownership

The platform ownership can be obtained as follows. Note that the OCA can be located on a different system, for simplicity, it can also be the PO.  Note that the platform owner certificate authority requires the sev-tool as well, otherwise the signatures and oca.cert must be manually created.

* Option 1: OCA private key located on server (pick this if possible)

```sh
# on host
openssl ecparam -name secp384r1 -genkey -noout -out oca_private.pem
openssl ec -in oca_private.pem -pubout -out oca_pub.pem
sevtool --set_externally_owned oca_private.pem
```

* Option 2: OCA private key not on server

```sh
# on host
sevtool --pek_csr
# Transfer CSR to PO
```

```sh
# on PO
openssl ecparam -name secp384r1 -genkey -noout -out oca_private.pem
openssl ec -in oca_private.pem -pubout -out oca_pub.pem
sevtool --sign_pek_csr pek_csr.cert oca_priv.pem
# transfer pek_csr.signed.cert and oca.cert back to host
```

```sh
# on host
sevtool --pek_cert_import pek_csr.signed.cert oca.cert
```

## Remote Attestation and Injection

In the following, we describe how the remote attestation is performed step by step. In the scripts, this is performed automatically.

__NOTE:__ As mentioned before, it is easer to have the server assume both the host and guest owner position at first.

__Verify host to guest owner__
* The PO authenticates itself and the hardware to the guest owner (GO), before the VM launch process is started.

```sh
# On host
# requires network connection, downloads ask_ark from AMD website
sevtool --export_cert_chain
# Transfer certs_export.zip to guest owner
```

```sh
# On guest owner

#verify ark and ask
unzip certs_export.zip
echo -n -e '\x1b\xb9\x87\xc3\x59\x49\x46\x06\xb1\x74\x94\x56\x01\xc9\xea\x5b' > naples_key_id
if [[ $(cmp -b -i 4:0 -n 16 ark.cert naples_key_id) == "" ]]; then device_type=naples; ask_size=832; else device_type=rome; ask_size=1600; fi
# obtain respective ark from amd website
wget "https://developer.amd.com/wp-content/resources/ask_ark_$device_type.cert"
# separate downloaded cert into ASK and ARK
head -c "$ask_size" "ask_ark_$device_type.cert" > "ask_$device_type.cert"
dd < /dev/zero bs="$ask_size" count=1 > "ark_$device_type.cert"
dd conv=notrunc if="ask_ark_$device_type.cert" of="ark_$device_type.cert" skip="$ask_size" iflag=skip_bytes 2>/dev/null
# Compare ASK and ARK with AMD's
if [[ $(cmp "ark_$device_type.cert" ark.cert 2>&1) == "" ]]; then echo "ARK Match!"; else echo "Failed."; fi
if [[ $(cmp "ask_$device_type.cert" ask.cert 2>&1) == "" ]]; then echo "ASK Match!"; else echo "Failed."; fi

# verify cert chain
sevtool --validate_cert_chain
  ```

__Launch VM and measure on host__
* The VM is launched an measured to assure that the correct settings / components are used.
* See below launch command options on how to start the VM

```sh
# on guest owner
# Requires PDH in same folder
# Writes the unencrypted TK (TIK and TEK) to a tmp file so it can be read in during package_secret
sevtool --generate_launch_blob 0
# agree on a VM iamge and OVMF or send own image, OVMF_CODE (and OVMF_VARS) files to host
# send launch blob and GODH (base64) to host
```

```sh
# on host
# use received launch blob, agreed OVMF and godh.cert to start VM
cat godh.cert | base64 > godh.cert.base64
cat launch_blob.bin | base64 > launch_blob.bin.base64

# Start VM
# <QEMU command option 2 or similar>

# obtain Launch_Measure: [digest|MNonce] (see QMP section for information)
# port as set when QEMU was started
data=$( (sleep .01; echo '{ "execute": "qmp_capabilities" }'; sleep .01; echo '{"execute": "query-sev-launch-measure"}'; sleep .01; echo "^]"; ) | nc -U -N qmp_sock | grep "data")
echo "$data" | sed -e "s,.*{\"data\".*\"\(.*\)\".*,\1," > launch_measure.base64
# Transfer launch_measure.base64 to guest owner
```

__Verify Measure on guest owner__

* The guest owner calculates the expected measurement after receiving the launch measurement from the host and compares both. For more information, see [API Chapter 6.5](https://developer.amd.com/wp-content/resources/55766.PDF) on how the launch_measure was computed. Note that the below steps are for SEV.
* The command takes multiple arguments (all of them in hex format). See [online documentation](https://github.com/AMDESE/sev-tool/blob/master/readme.md) for more information.

```sh
# on guest owner
# Obtain API from received PEK cert
API=$(dd if=pek.cert ibs=1 skip=4 count=2 2>/dev/null | xxd -p)
API_MAJOR=$(echo "$API" | cut -c1-2)
API_MINOR=$(echo "$API" | cut -c3-4)
# Host shared this number with GO
# e.g. from sevtool --platform_status.
# Note: Command returns value in decimal format (22), here it is required in hex (16)
BUILD=16
# Set by GO
POLICY=01
This is argument digest in calc_measurement
# Note that it is sha384sum for Rome
DIGEST=$(sha256sum OVMF_CODE.fd | awk '{print $1;}')
# received from host
launch_measure=$(cat launch_measure.base64)
MEASURE=$(echo "$launch_measure" | base64 -d | xxd -p -s 0 -l 32 | tr -d '\n')
MNONCE=$(echo "$launch_measure" | base64 -d | xxd -p -s 32 | tr -d '\n')
TIK=$(xxd -p tmp_tk.bin  | tr -d '\n'  | tail -c 32)

sevtool --verbose --calc_measurement 04 "$API_MAJOR" "$API_MINOR" "$BUILD"  "$POLICY" "$DIGEST"  "$MNONCE" "$TIK"

# Compare to value obtained from launch_measure (from host) with calc_measurement output (calc_measurement_out.txt)
if [[ $(cat calc_measurement_out.txt) == "$MEASURE" ]]; then echo "Success!"; else echo "Failed check"; fi
```

__Inject Secret into Guest__

* Requires VM to be run with the AMD's OVMF and QEMU
* VM must support SEV and have it enabled

```sh
# on guest owner
# wraps secret in correct table with header and content guids
./create_secret.py <your disk encryption password> secret.txt
# must have current calc_measure_out.txt in same folder
sevtool --package_secret
# transfer packaged_secret.bin and packaged_secret_header.bin to host
```

```sh
# on host
# inject package_secret with header into VM
SECRET=$(cat packaged_secret.bin | base64)
SECRET_HEADER=$(cat packaged_secret_header.bin | base64)
# GPA (guest physical address at which to inject) is not needed with QEMU patches applied

# inject secret
# ADAPT qmp_sock path if required
(echo; sleep .01; echo '{ "execute": "qmp_capabilities" }'; sleep .01; echo '{ "execute": "sev-inject-launch-secret", "arguments": { "packet-header": "'$SECRET_HEADER'", "secret": "'$SECRET'"}}';sleep .01;) | nc -N -U qmp_sock

# Manually continue execution
(echo; sleep .01; echo '{ "execute": "qmp_capabilities" }'; sleep .01; echo '{ "execute": "cont"}'; sleep .01) | nc -N -U qmp_sock

# The VM should start and -depending on which OVMF/grub/initramfs-
# successfully decrypt the disk using the injected secret
```

## VM deployment in Detail

__Dos and Don'ts:__
* __-enable-kvm:__  This ensures that the actual firmware is used to encrypt and none of the SEV components are emulated
* __OVMF:__ We use AMD's OVMF as other variations may not support all required features for SEV and SEV secret injection and support custom VM disks. The OVMF provided with the ovmf package supports SEV features for unmodified VMs
* __VMs:__ In our case, modified VMs require modified OVMFs (more precisely modified grubs inside the OVMF) to still be capable of booting
* __Port forwards:__ We use port forwarding to enable ssh-connections to the VM
* __Calc_measurement:__ When calculating the measurement, values must be provided in the correct format. The sev-tool expects all numbers in __hex format__
* __Drives, OVMF and networking:__ When changing certain QEMU flags (e.g., network device, disk types), the network interface name may change as well, thus affecting connectivity inside the VM. It is easiest not to modify these flags.
* __Launch policy:__ Note that bit 2 sets AMD SEV-ES required to true. In order for this to work, the host BIOS must be configured accordingly. This is untested.

__Commands:__

The following commands start a VM with AMD SEV encryption enabled.

```sh
# modify policy accordingly if desired
# Adapt names / paths
policy=0
image="debian.qcow2"
# Uses regular OVMF files, e.g., from ovmf package
ovmf="OVMF_CODE.fd"
ovmf_vars="OVMF_VARS.fd"
```

```sh
# Option 1: No Remote attestation
# VM with SEV-features enabled and grub. VM is supported by OVMF from official package
qemu-system-x86_64 \
-enable-kvm \
-cpu EPYC \
-machine q35,vmport=off,memory-encryption=sev0 \
-object sev-guest,id=sev0,cbitpos=47,reduced-phys-bits=1,policy="$policy" \
-m 2G \
-drive if=pflash,format=raw,unit=0,file="$ovmf",readonly=on \
-drive if=pflash,format=raw,unit=1,file="$ovmf_vars" \
-drive file="$image",format=qcow2 \
-nographic \
-serial mon:stdio \
-nodefaults \
-netdev user,id=vmnic,hostfwd=tcp::5555-:22 \
-device e1000,netdev=vmnic
```

```sh
# Option 2: With remote attestation and qmp server
# (See remote attestation steps beforehand for godh/ launch blob)
# VM with SEV-features enabled and grub. VM is supported by OVMF from official package
qmp_sock="qmp_sock"
godh_file="godh.cert"
launch_blob_file="launch_blob.bin"

godh=$(base64 -w 0 "$godh_file")
launch_blob=$(base64 -w 0 "$launch_blob_file")

qemu-system-x86_64 \
-enable-kvm \
-cpu EPYC \
-machine q35,vmport=off,memory-encryption=sev0 \
-object sev-guest,id=sev0,cbitpos=47,reduced-phys-bits=1,policy="$policy",dh-cert-file="$godh",session-file="$launch_blob" \
-m 2G \
-drive if=pflash,format=raw,unit=0,file="$ovmf",readonly=on \
-drive if=pflash,format=raw,unit=1,file="$ovmf_vars" \
-drive file="$image",format=qcow2 \
-nographic \
-serial mon:stdio \
-nodefaults \
-netdev user,id=vmnic,hostfwd=tcp::5555-:22 \
-device e1000,netdev=vmnic \
-qmp unix:"$qmp_sock",server,nowait
```

```sh
# Option 3: With remote attestation, launch injection
# IMPORTANT : Requires specific AMD OVMF and VM image
# No more OVMF VARS required (all defined in OVMF)
sev_ovmf=OVMF.fd
qmp_sock="qmp_sock"

godh=$(base64 -w 0 "$godh_file")
launch_blob=$(base64 -w 0 "$launch_blob_file")

qemu-system-x86_64 \
-enable-kvm \
-cpu EPYC \
-machine q35,vmport=off,memory-encryption=sev0 \
-object sev-guest,id=sev0,cbitpos=47,reduced-phys-bits=1,policy="$policy",dh-cert-file="$godh",session-file="$launch_blob" \
-m 2G \
-drive if=pflash,format=raw,unit=0,file="$sev_ovmf",readonly=on \
-drive file="$image",format=qcow2 \
-nographic \
-serial mon:stdio \
-nodefaults \
-netdev user,id=vmnic,hostfwd=tcp::5555-:22 -device e1000,netdev=vmnic  \
-qmp unix:"$qmp_sock",server,nowait -S
```

```sh
# Option 4: With additional debug info: Tracks all SEV-specific commands
# see qemu-system-x86_64 -d trace:help
# and qemu-system-x86_64 -d help
<Insert option> -D ./log.txt -d trace:kvm_sev_init,trace:kvm_sev_launch_measurement,trace:kvm_sev_change_state,trace:kvm_sev_launch_start,trace:kvm_sev_launch_update_data,trace:kvm_sev_launch_finish
# For migration, add: trace:kvm_sev_send_start,trace:kvm_sev_send_update_data,trace:kvm_sev_send_finish,trace:kvm_sev_receive_start,trace:kvm_sev_receive_update_data,trace:kvm_sev_receive_finish,trace:kvm_sev_save_bitmap,trace:kvm_sev_load_bitmap

# For injection, add: trace:kvm_sev_launch_secret
```

```sh
# Option 5: Syscall trace debug (beware walls of text)
strace <Insert Option> 2> trace.log
```

__Step-by-step explanation:__ \
Some flags are split into their respective components for more clarity
* `qemu-system-x86_64`: The command itself
*  `-enable-kvm`: Makes sure the actual AMD SEV firmware is used
* `-cpu EPYC`: Specifies type of underlying cpu type. Alternatively,  `-cpu host` automatically matches the host machine. See `qemu-system-x86_64 -cpu help` for more options. It should be something EPYC related.
* `-machine q35`: Machine should be set to q35 or equivalent (legacy i440fx [is discouraged](https://libvirt.org/kbase/launch_security_sev.html#machine-type)). See `qemu-system-x86_64 -machine help` for more options.
* `-machine vmport=off`: vmport (VMWare ioport emulation) is enabled by default (or set to auto) but not required, thus we turn it off explicitly
* `-machine memory-encryption=sev0`: This, together with the below objects enables SEV. Remove both to not use SEV.
* `-object sev-guest, id=sev0, cbitpos=47, reduced-phys-bits=1`: Enables SEV. Value `cbitpos=47` depends on the used hardware.
* `-object policy=$policy`: This specifies the policy as defined by the  Guest Owner (or host if no guest owner). The default value is 0 if this parameter is ommitted. Note that for SEV-ES to work (policy bit 2), changes to the host BIOS are required
* `-m 2G`: Must be sufficient for VM - resulting bugs will be rather unspecific otherwise (e.g., disk unlock/cryptsetup fails even with correct password)
* `-drive if=pflash, format=raw, unit=0, file=$ovmf, readonly=on`: This goes together with below VARS (if it is not a custom OVMF build for SEV injection)
* `-drive if=pflash, format=raw, unit=1, file=$ovmf_vars`: These are not required for the AMD SEV OVMF. They can be modified during execution for example when modifying the boot config, thus a backup to be safe is advised. These must not be omitted if OVMF_CODE.fd is provided.
* `-drive file=$image, format=qcow2`: Raw and qcow2 are listed as valid image formats in AMD's guide, we used qcow2 due to its flexibility
* `-nographic`: VMs can be run in console only, thus not requiring graphics. If graphical output is desired/required, option `-vnc` or a graphical window may be used
* `-serial mon:stdio`: Defines a console over which VM output is displayed
* `-nodefaults`: Stops QEMU from adding unnecessary components such as a floppy disk or the like. This may fail to boot the VM if not every single required component is explicitly listed
* `-netdev user,id=vmnic,hostfwd=tcp::5555-:22` This is a simple network setup with one port on the server side (5555) being forwarded to the VM (22)
* `-device e1000, netdev=vmnic`: Part of the above network setup. Virtio network devices are not supported for the first generation of SEV to our knowledge
* Authentication / Attestation: These are optional and can be ignored if no remote attestation is performed / launch measures are used:
  + `-object dh-cert-file=$godh, session-file=$launch_blob`: variable $godh specifies the Guest Owner Diffie Hellman public Key in base64 encoding, $launch_blob the launch_blob also in base64 encoding
  + `-qmp unix:$qmp_sock, server, nowait`: Allows for custom commands and queries to be sent to our QEMU-instance. See the [QMP documentation](https://wiki.qemu.org/Documentation/QMP) for more information. The qmp server can either be accessed through a unix socket or a port using `-qmp tcp:localhost:4444, server, nowait`
  + `-S`: This stops the VM from starting automatically. Otherwise, this would set the VM in state running, which prevents the injection of the launch / package secret. To continue VM execution, "cont" command must be sent via the monitor (see below).
* (Optional) `-serial mon:telnet:127.0.0.1:6666,server,nowait` : This allows to connect to port 6666 using telnet and follow the boot process of the VM as soon as it is run. This helps if there are netork / connectivity issues inside of the VM

__Final Check:__

To check for active SEV inside VM, run the following command.

```sh
$ dmesg | grep -i sev
[    0.054563] AMD Secure Encrypted Virtualization (SEV) active
```

### Bugs and Fixes

* __Permission denied:__ If the VM returns with: \
 `qemu-system-x86_64: sev_guest_init: Failed to open /dev/sev 'Permission denied'`

Permissions to `/dev/sev` must be (re-) configured (see chmod/chown commands)
* __AMD SEV-ES:__ If the QEMU-command returns with error code `-16` along the lines of

`qemu-system-x86_64: sev_guest_init: failed to initialize ret=-16 fw_error=0` \
 `qemu-system-x86_64: failed to initialize KVM: Operation not permitted`

  and the trace log reveals that `-EBUSY` returned:

 `ioctl(14, KVM_MEMORY_ENCRYPT_OP, 0x7ffd9febf640) = -1 EBUSY (Device or resource busy)`

  The BIOS may be configured in a way where it does not support SEV (or SEV-ES if policy 0x02 is used). The corresponding BIOS setting looks similar to this:

 `Advanced>CPU Configuration>SEV-ES ASID Space Limit = 1`

  1 means no SEV-ES VMs are allowed, each increase allows one more AMD SEV-ES VM: 2 means 1, 3 means 2 etc. (default is 1). See [this issue](https://github.com/AMDESE/AMDSEV/issues/33) for reference.
* __OVMF Loop:__ If the boot process keeps looping after the OVMF and not proceeding past the grub / kernel, it is possible that either the wrong VM kernel is loaded or that the VM kernel does not support AMD SEV or it is not enabled
* __Bad measurement:__
  + If the launch fails due to a bad measurement, it is possible the wrong PDH was used when creating the launch blob. In case the platform owner changed between blob generation and VM launch, the PDH changed as well which invalidates any previously created launch blobs. Furthermore, all formatting must be in hex.
  + If injection fails due to bad measurement, it is possible the wrong  calc_measurement_out.bin and tmp_tk.bin were used during package secret creation

## QMP

Once a QEMU instance is launched with the qmp flag (see QEMU command option 2) - even if it was stopped at start or only reached the OVMF UEFI shell -, the QEMU Monitor Protocol can be used to run more complex queries and commands on said instance. The following commands are of interest.

__Note:__ The qmp server can be contacted through a port or a unix socket (depending on the QEMU command), this here describes the unix variation. For ports, use `telnet localhost <port>` instead.

__Note:__ When connecting to the qmp server, the correct server state has to be set with a call to execute qmp_capabilities, see [the documentation ](https://wiki.qemu.org/Documentation/QMP) (Under category "Trying by hand", step 4).

```sh
# specify which socket (VM)
qmp_sock=qmp_sock
```

### Obtaining the Launch measure:

```sh
# Option 1:
(echo; sleep .01; echo '{ "execute": "qmp_capabilities" }'; sleep .01; echo '{"execute": "query-sev-launch-measure"}'; sleep .01) | nc -U -N "$qmp_sock"

# Option 2: manually execute
nc -U "$qmp_sock"
# on qmp server
{ "execute": "qmp_capabilities" }
{ "execute": "query-sev-launch-measure"}
```

### Query SEV features

This information can also be obtained through the sevtool. See `sevtool --platform_status`

```sh
# Option 1:
(echo; sleep .01; echo '{ "execute": "qmp_capabilities" }'; sleep .01; echo '{ "execute": "query-sev" }'; sleep .01) | nc -U -N "$qmp_sock"

# Option 2: manually execute
nc -U "$qmp_sock"
# on qmp server
{ "execute": "qmp_capabilities" }
{ "execute": "query-sev" }
```

### Query SEV capabilities

This information can also be obtained through the sevtool. See `sevtool --export_cert_chain`

```sh
# Option 1:
(echo; sleep .01; echo '{ "execute": "qmp_capabilities" }'; sleep .01; echo '{"execute": "query-sev-capabilities"}'; sleep .01) | nc -U -N "$qmp_sock"

# Option 2: manually execute
nc -U "$qmp_sock"
# on qmp server
{ "execute": "qmp_capabilities" }
{"execute": "query-sev-capabilities"}
```

### Query Commands

This displays a list of all possible commands. The list contains several commands for migration, e.g., query-migrate and query-migrate-parameters

```sh
# Option 1:
(echo; sleep .01; echo '{ "execute": "qmp_capabilities" }'; sleep .01; echo '{ "execute": "query-commands" }'; sleep .01) | nc -U -N "$qmp_sock"

# Option 2: manually execute
nc -U "$qmp_sock"
# on qmp server
{ "execute": "qmp_capabilities" }
{ "execute": "query-commands" }
```

### Inject launch secret

This is only available in newer QEMU versions (greater 5.2.0, officially 6.0). See [online documentation](https://qemu.readthedocs.io/en/latest/interop/qemu-qmp-ref.html) as well as the [source code](https://github.com/qemu/qemu/blob/master/qapi/misc-target.json). The GPA may vary depending on the OVMF build.
Since QEMU 6.0, this field is optional and will be calculated automatically if unspecified.

```sh
# Option 1:
(echo; sleep .01; echo '{ "execute": "qmp_capabilities" }'; sleep .01; echo '{ "execute": "sev-inject-launch-secret", "arguments": { "packet-header": "<base64 header str>", "secret": "<base64 secret str>", "*gpa": "<guest physical address to which to inject, uint64>"}}'; sleep .01) | nc -U -N "$qmp_sock"

# Option 2: manually execute
nc -U "$qmp_sock"
# on qmp server
{ "execute": "qmp_capabilities" }
{ "execute": "sev-inject-launch-secret", "arguments": { "packet-header": "<base64 header str>", "secret": "<base64 secret str>", "gpa": "<guest physical address to which to inject, uint64>"}}
```

### Continue Execution

In case the VM was set to not automatically start upon invocation (see flag `-S` ), the following command will continue the execution.

```sh
# Option 1
(echo; sleep .01; echo '{ "execute": "qmp_capabilities" }'; sleep .01; echo '{ "execute": "cont"}'; sleep .01) | nc -U -N "$qmp_sock"

# Option 2: manually execute
nc -U "$qmp_sock"
# on qmp server
{ "execute": "qmp_capabilities" }
{"execute": "cont"}
```
