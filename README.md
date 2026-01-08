## Overview

Proxmox cluster in Docker. Learn, test, break, and repeat.

- **Fast iteration** — Spin up, tear down, repeat in seconds
- **Cluster simulation** — Test live migration, clustering, and multi-node management
- **Automation testing** — Validate Terraform, Ansible, or scripts
- **Shared storage** — Mount ISOs, backups, and disk images across all nodes
- **Dual-Stack Networking** — IPv4 and IPv6 support with pre-configured NAT bridges
- **KVM & LXC ready** — Virtual machines and containers work out of the box
- **Central management** — Optional [Proxmox Datacenter Manager](proxmox-datacenter-manager) container included
- **[ARM64 support](pxvirt)** — Proxmox VE on your favorite ARM platform, powered by [PXVIRT](https://docs.pxvirt.lierfang.com/en/README.html)

---

## Requirements

- Modern Linux host with kernel 6.8+
- [Docker Engine](https://docs.docker.com/engine/install/)
- Intel VT-x / AMD-V enabled
- macOS: Use [OrbStack](https://orbstack.dev/) instead of Docker Desktop
- Windows 11 with Docker Desktop (WSL2):
   - WSL kernel version 6.6+ (`wsl --version`)
   - Nested virtualization enabled in WSL Settings

---

## Quick Start
Standalone node with `docker run`:
> [!Note]
> On ARM64 platforms, use `proxmox-ve-arm64` instead of `proxmox-ve`
```bash
docker run -d --name pve-1 --hostname pve-1 \
    -p 2222:22 -p 3128:3128 -p 8006:8006 \
    --restart unless-stopped  \
    --privileged --cgroupns=private \
    --device /dev/kvm \
    -v /dev/vfio:/dev/vfio \
    -v /usr/lib/modules:/usr/lib/modules:ro \
    -v /sys/kernel/security:/sys/kernel/security \
    -v ./VM-Backup:/var/lib/vz/dump \
    -v ./ISOs:/var/lib/vz/template/iso \
    ghcr.io/longqt-sea/proxmox-ve
```
Replace `./ISOs` with the path to your ISO folder.

Set root password:
```
docker exec -it pve-1 passwd
```

Access the web UI at `https://localhost:8006/` (accept the self-signed cert).

---

## Multi-Node Cluster
Deploy 3-node cluster using Docker Compose:
- Create a project directory and cd into it:
   ```
   mkdir pve_cluster; cd pve_cluster
   ```

- Create a `compose.yml` file in the `pve_cluster` directory with the following content:
```yaml
services:
  # First node
  pve-1:
    image: ghcr.io/longqt-sea/proxmox-ve
    container_name: pve-1
    hostname: pve-1
    privileged: true
    restart: unless-stopped
    cgroup: private
    shm_size: 1g
    devices:
      - /dev/kvm
    networks:
      dual_stack:
        ipv4_address: 10.0.99.1
        ipv6_address: fd00::1

    # Port mapping only required for Docker Desktop or LAN access from other machines.
    ports:
      - "2222:22"
      - "3128:3128"
      - "8006:8006"   # First node container port 8006 maps to host port 8006

    volumes:
      - /usr/lib/modules:/usr/lib/modules:ro        # Required for loading kernel modules
      - /sys/kernel/security:/sys/kernel/security   # Optional, needed for LXC
      - ./VM-Backup:/var/lib/vz/dump                # Shared storage for VM/LXC backups
      - ./ISOs:/var/lib/vz/template/iso             # Shared storage for ISO files


  # Second node
  pve-2:
    image: ghcr.io/longqt-sea/proxmox-ve
    container_name: pve-2
    hostname: pve-2
    privileged: true
    restart: unless-stopped
    cgroup: private
    shm_size: 1g
    devices:
      - /dev/kvm
    networks:
      dual_stack:
        ipv4_address: 10.0.99.2
        ipv6_address: fd00::2

    # Port mapping only required for Docker Desktop or LAN access from other machines.
    ports:
      - "2223:22"
      - "3129:3128"
      - "8007:8006"   # Second node container port 8006 maps to host port 8007

    volumes:
      - /usr/lib/modules:/usr/lib/modules:ro        # Required for loading kernel modules
      - /sys/kernel/security:/sys/kernel/security   # Optional, needed for LXC
      - ./VM-Backup:/var/lib/vz/dump                # Shared storage for VM/LXC backups
      - ./ISOs:/var/lib/vz/template/iso             # Shared storage for ISO files


  # Third node
  pve-3:
    image: ghcr.io/longqt-sea/proxmox-ve
    container_name: pve-3
    hostname: pve-3
    privileged: true
    restart: unless-stopped
    cgroup: private
    shm_size: 1g
    devices:
      - /dev/kvm
    networks:
      dual_stack:
        ipv4_address: 10.0.99.3
        ipv6_address: fd00::3

    # Port mapping only required for Docker Desktop or LAN access from other machines.
    ports:
      - "2224:22"
      - "3130:3128"
      - "8008:8006"   # Third node container port 8006 maps to host port 8008

    volumes:
      - /usr/lib/modules:/usr/lib/modules:ro        # Required for loading kernel modules
      - /sys/kernel/security:/sys/kernel/security   # Optional, needed for LXC
      - ./VM-Backup:/var/lib/vz/dump                # Shared storage for VM/LXC backups
      - ./ISOs:/var/lib/vz/template/iso             # Shared storage for ISO files


  # Optional: Proxmox Datacenter Manager
  pdm:
    image: ghcr.io/longqt-sea/proxmox-datacenter-manager
    container_name: pdm
    hostname: pdm
    restart: unless-stopped
    cgroup: private
    shm_size: 1g
    cap_add:
      - SYS_ADMIN
      - NET_ADMIN
    security_opt:
      - seccomp=unconfined
      - apparmor=unconfined
    networks:
      dual_stack:
        ipv4_address: 10.0.99.4
        ipv6_address: fd00::4

    # Port mapping only required for Docker Desktop or LAN access from other machines.
    ports:
      - "2225:22"
      - "8443:8443"


# Dual-stack network for this cluster
networks:
  dual_stack:
    enable_ipv6: true
    ipam:
      config:
        - subnet: 10.0.99.0/24
          gateway: 10.0.99.99
        - subnet: fd00::/64
          gateway: fd00::99
```
Bring it up:
```
docker compose up -d
```

Set root password for all nodes:
> Replace `123` with your own password
- Linux/macOS Terminal:
   ```bash
   for c in pve-1 pve-2 pve-3; do docker exec $c sh -c 'echo "root:123" | chpasswd'; done
   ```
- Windows Powershell:
   ```pwsh
   "pve-1","pve-2","pve-3" | % { docker exec $_ sh -c 'echo "root:123" | chpasswd' }
   ```

> [!Tip]
> Access nodes like this to avoid authentication conflicts ("invalid PVE ticket 401" errors caused by cookie collisions):
>
> | Environment | How to access nodes |  Example |
> |------------|---------------------|----------|
> | Docker Engine (Linux) | Access nodes directly via container IPs | `https://[fd00::1]:8006`<br>`https://[fd00::2]:8006`<br>`https://[fd00::3]:8006` |
> | Docker Desktop (Windows) | Use different loopback address | `https://127.0.0.1:8006`<br>`https://127.0.0.2:8007`<br>`https://127.0.0.3:8008` |
> | Docker Desktop (macOS) | Use separate browser profile for each node | `Multiple Chrome profile`<br>`Or different browser`<br> |

> [!Note]
> To create the cluster, go to **System → Network** on **pve-1** node, edit `eth0` interface as shown in the image below.
>
> Next, go to **Datacenter → Cluster → Create Cluster** and copy **Join Information**.
>
> On other nodes, go to **Datacenter → Cluster → Join Cluster**, paste the copied **Join Information**, enter root password.
>
> <p align="center">
>   <img src="https://github.com/LongQT-sea/containerized-proxmox/raw/main/.github/pve-1_eth0_interface.png" alt="PVE network">
> </p>

Nodes can reach each other over hostname or IP address:
| hostname | IPv4       | IPv6    |
|----------|------------|---------|
| pve-1    | 10.0.99.1  | fd00::1 |
| pve-2    | 10.0.99.2  | fd00::2 |
| pve-3    | 10.0.99.3  | fd00::3 |
| pdm      | 10.0.99.4  | fd00::4 |

To tear down the cluster:
```
docker compose down -t 0
```

---

## Ports

| Port | Purpose |
|------|--------------|
| 8006 | Proxmox VE Web UI |
| 3128 | SPICE proxy |
| 22 | OpenSSH |
| 8443 | Proxmox Datacenter Manager Web UI |

## Volumes

| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| ./VM-Backup | /var/lib/vz/dump | VM backups |
| ./ISOs | /var/lib/vz/template/iso | ISO images |

## Networks

- `vmbr1` - NAT network for VM and LXC, works out of the box
- `vmbr2` - Empty bridge, configure it yourself, maybe with macvlan, veth or passthrough a physical NIC

---

> [!Note]
> When running with `podman`, make sure to run as root or with `sudo`, rootless Podman does not work even with `--privileged`.

> [!Warning]
> This setup uses the `--privileged` flag. The container can do almost everything the Linux host can do. Use with caution.

---

## Known Limitations

### High Availability (HA) Not Supported

Proxmox HA requires hardware watchdog fencing, which cannot work in containers:

- Linux `/dev/watchdog` can only be used by one process at a time
- Containers cannot fence (forcibly reboot) each other
- VMs added to HA will stay stuck in "queued" state

**For HA learning, use bare-metal or nested VMs instead.**

---

## License

This project is licensed under the GPLv3 or later (see [LICENSE](LICENSE) file).

---

## Disclaimer

This project is provided “as‑is”, without any warranty, for educational and research purposes. In no event shall the authors or contributors be liable for any direct, indirect, incidental, special, or consequential damages arising from use of the project, even if advised of the possibility of such damages.

All product names, trademarks, and registered trademarks are property of their respective owners. All company, product, and service names used in this repository are for identification purposes only.
