# Proxmox Datacenter Manager inside container

Proxmox Datacenter Manager in Docker, why not!

## Quick start
### With `docker run`:
> [!Note]
> - Remove `--detach` if you want an interactive console, to escape, hold CTRL then press P + Q
> - Run `docker attach pdm` to reattach later if needed
```bash
docker run --detach -it --name pdm --hostname pdm \
    -p 8443:8443 -p 2222:22 \
    --restart unless-stopped \
    --cgroupns=private \
    --security-opt seccomp=unconfined \
    --security-opt apparmor=unconfined \
    --cap-add=SYS_ADMIN \
    --cap-add=NET_ADMIN \
    --env PASSWORD=123 \
    ghcr.io/longqt-sea/proxmox-datacenter-manager
```

Default root password: `123`

---

### With Docker Compose:
```yaml
services:
  pdm:
    image: ghcr.io/longqt-sea/proxmox-datacenter-manager
    container_name: pdm
    hostname: pdm
    restart: unless-stopped
    stdin_open: true
    tty: true
    cgroup: private
    cap_add:
      - SYS_ADMIN
      - NET_ADMIN
    security_opt:
      - seccomp=unconfined
      - apparmor=unconfined
    ports:
      - "2222:22"
      - "8443:8443"
    environment:
      - PASSWORD=123
```
Bring it up:
```
docker compose up -d
```

Default root password: `123`

To attach to the console:
```
docker attach pdm
```
To escape, hold CTRL then press P + Q

Access the web UI at https://Docker-IP:8443 (accept the self-signed cert).
