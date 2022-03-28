# VM setup

The following guide explains how to create a setup where multiple VMs/ machines /servers are part of a VPN using wireguard. This includes:
* The setup of the VPN with router (e.g., in SEV-VM), client (e.g., in VM) and container VM (in SEV-VM)
* The installation of a container runtime and deployment of a container with an exemplary webserver

## Wireguard setup

Install and configure wireguard on/in router (VM), client (VM) and the VM later running the container (container VM).
* Transfer `VM-setup` directory to all entities
* The below commands install and configure wireguard:

```sh
  # On all machines/VMs
  # Install required networking tools
  sudo apt update
  sudo apt install net-tools nftables iptables
  # install wireguard
  wget http://ftp.us.debian.org/debian/pool/main/w/wireguard/wireguard-tools_1.0.20210223-1_amd64.deb
  sudo apt install ./wireguard-tools*.deb
  # prepare node / wg interface
  ./prepare-node.sh
```

* Setup on router VM: The router VM port 51820 (default wireguard port) must be reachable, e.g., through port forwarding
* Start the wiregaurd router as follows:

```sh
# On router (VM)
sudo ./start-wireguard-interface.sh 1
```

* Obtain the public keys from both client (VM) / container VM:

```sh
  # On client / container VM
  cat peer.publickey
```

* Add peers to the router:

```sh
  # On router (VM)
  # Add peers, repeat for each peer publickey
  # Remember the index / printed command & number for each peer
  sudo ./add-peer.sh <peer publickey>
  # Copy-paste printed command to peers
```

*  __Note:__ The peers periodically inform the router of their IP since adding new peers wipes the established peers' IPs. This may take up to 1 second as per configuration.
* To setup the peers, complete the previously obtained commands (default port is 51820):

```sh
  # On client / container VM
  # USE previously obtained command for this peer
  # ADAPT HERE: add IP and port through which router VM port 51820 can be reached
  sudo ./add-router.sh <router publickey file> <index> <control node ip:port>
```

## Wireguard Shutdown and Restart

To remove the wireguard interface, run:

```sh
  sudo ip link del wg0
```

To restart wireguard after a reboot: (start with router (VM) first if it was also rebooted)

```sh
  # On rebooted machine
  # ADAPT HERE: use previously alotted IP index
  sudo ./start-wireguard-interface.sh <index>
```

## Container Deployment

* See the guide on how to install the container runtime [docker](https://docs.docker.com/engine/install/debian/) inside of the VM and add the user to the docker group
* To build the container, transfer the `container` directory to the VM (e.g., using scp) and run:

```sh
  # In container VM
  docker build VM-setup/container/ --tag my-container
```

* The following command runs the container in detached mode:

```sh
  # In container VM
  docker run --rm --name=test-instance -d -p 8000:7777 my-container
```

* The server (container) inside the SEV-VM can now be reached through the wireguard IP:

```sh
  # On client (VM)
  # ADAPT IP index if needed (last 255bit of IP)
  vm_index=2
  # reach server on container VM
  wget -qO- http://192.168.18.$vm_index:8000/
  wget -O 1G http://192.168.18.$vm_index:8000/1G
```
