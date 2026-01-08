# Proxmox Datacenter Manager inside container

Proxmox Datacenter Manager in Docker, why not!

## Quick start
With `docker run`:
```bash
docker run -d --name pdm --hostname pdm \
    -p 8443:8443 -p 2222:22 \
    --restart unless-stopped \
    --cgroupns=private \
    --security-opt seccomp=unconfined \
    --security-opt apparmor=unconfined \
    --cap-add=SYS_ADMIN \
    ghcr.io/longqt-sea/proxmox-datacenter-manager
```

Set root password:
```
docker exec -it pdm passwd
```

With Docker Compose:
```yaml
services:
  pdm:
    image: ghcr.io/longqt-sea/proxmox-datacenter-manager
    container_name: pdm
    hostname: pdm
    restart: unless-stopped
    cgroup: private
    cap_add:
      - SYS_ADMIN
    security_opt:
      - seccomp=unconfined
      - apparmor=unconfined
    ports:
      - "2222:22"
      - "8443:8443"
```
Bring it up:
```
docker compose up -d
```

Set root password:
```
docker exec -it pdm passwd
```

Access the web UI at https://Docker-IP:8443 (accept the self-signed cert).
