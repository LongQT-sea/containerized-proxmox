## Overview
### Proxmox cluster in Docker. Learn, test, break, repeat.

This project provides containerized Proxmox Virtual Environment for development, testing, and learning purposes. Spin up single nodes or entire HA clusters in seconds—perfect for validating infrastructure-as-code, testing failover scenarios, or exploring Proxmox features without dedicated hardware.

## Features

- **Fast iteration** — Spin up, tear down, repeat in seconds
- **Cluster simulation** — Test HA, failover, and live migration
- **Automation testing** — Validate Terraform, Ansible, or scripts
- **Shared storage** — Mount ISOs, backups, and disk images across all nodes
- **Dual-Stack Networking** — IPv4 and IPv6 support with pre-configured NAT bridges
- **KVM and LXC support** — Works out of the box
- **Central management** — Optional [Proxmox Datacenter Manager](proxmox-datacenter-manager) container included
- **[ARM64 support](pxvirt)** — Proxmox VE on your favorite ARM platform, powered by [PXVIRT](https://docs.pxvirt.lierfang.com/en/README.html)

---

## Requirements

- A modern Linux host with kernel 6.8+
- [Docker Engine](https://docs.docker.com/engine/install/)
- CPU with virtualization support (Intel VT-x / AMD-V)

> [!Note]
> Docker Desktop required nested virtualization, e.g. WSL2: [nestedVirtualization](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#main-wsl-settings)

---

## Quick Start
Standalone node with `docker run`:
> [!Note]
> For ARM64 platforms (Apple Silicon, Raspberry Pi 5, Ampere, AWS Graviton .metal),
> replace `proxmox-ve` with `proxmox-ve-arm64`
```bash
docker run -d --name pve-1 --hostname pve-1 \
    -p 2222:22 -p 3128:3128 -p 8006:8006 \
    --restart unless-stopped  \
    --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup \
    -v /dev/vfio:/dev/vfio \
    -v /usr/lib/modules:/usr/lib/modules:ro \
    -v /sys/kernel/security:/sys/kernel/security \
    -v ./VM-Backup:/var/lib/vz/dump \
    -v ./ISOs:/var/lib/vz/template/iso \
    ghcr.io/longqt-sea/proxmox-ve
```
Replace `./ISOs` with the path to your ISO folder.

Set root password and restart the container at least once:
```
docker exec -it pve-1 passwd
docker restart pve-1
```

Access the web UI at `https://localhost:8006/` (accept the self-signed cert).

---

## Multi-Node Cluster
Deploy a production-like 3-node HA cluster with shared storage using Docker Compose:
```
mkdir pve_cluster && cd pve_cluster

nano docker-compose.yml
```

Paste the content below into nano, save with Ctrl+X, Y, Enter.
```yaml
services:
  # First node
  pve-1:
    image: ghcr.io/longqt-sea/proxmox-ve
    container_name: pve-1
    hostname: pve-1
    privileged: true
    restart: unless-stopped
    cgroup: host
    shm_size: 1g
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
      - /sys/fs/cgroup:/sys/fs/cgroup               # Required for systemd init
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
    cgroup: host
    shm_size: 1g
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
      - /sys/fs/cgroup:/sys/fs/cgroup               # Required for systemd init
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
    cgroup: host
    shm_size: 1g
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
      - /sys/fs/cgroup:/sys/fs/cgroup               # Required for systemd init
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
    cgroup: host
    shm_size: 1g
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup
    cap_add:
      - ALL
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
```
docker exec -it pve-1 passwd
docker exec -it pve-2 passwd
docker exec -it pve-3 passwd
```

Restart all nodes at least once:
```
docker restart pve-1 pve-2 pve-3
```

> [!Tip]
> On Linux hosts, access nodes directly via their container IPs (e.g., `https://10.0.99.1:8006` or `https://[fd00::1]:8006`).
> 
> On Docker Desktop (Windows/macOS), use separate browser profiles for each node to avoid authentication conflicts ("invalid PVE ticket 401" errors caused by cookie collisions).

> [!Note]
> To create the cluster, edit the `eth0` interface like this on **pve-1** node, then go to Datacenter → Cluster → Create Cluster → Copy Join Information
> 
> Other nodes go to Datacenter → Cluster → Join Cluster → Paste the copied Join Information → Enter password
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
| 8006 | PVE Web UI |
| 3128 | SPICE proxy |
| 22 | SSH |
| 8443 | PDM Web UI |

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

## License

This project is licensed under the GPLv3 or later (see [LICENSE](LICENSE) file).

---

## Disclaimer

This project is provided “as‑is”, without any warranty, for educational and research purposes. In no event shall the authors or contributors be liable for any direct, indirect, incidental, special, or consequential damages arising from use of the project, even if advised of the possibility of such damages.

All product names, trademarks, and registered trademarks are property of their respective owners. All company, product, and service names used in this repository are for identification purposes only.
