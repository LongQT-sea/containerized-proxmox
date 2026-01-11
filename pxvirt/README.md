# PXVIRT / Proxmox VE for ARM64 inside container

Powered by [PXVIRT](https://docs.pxvirt.lierfang.com/en/README.html), a forked of Proxmox VE that support multiple CPU architectures, developed and maintained by [Lierfang](https://www.lierfang.com/).

## Quick Start
> [!Note]
> - Remove `--detach` if you want an interactive console, to escape, hold CTRL then press P + Q
> - Run `docker attach pxvirt-1 ` to reattach later if needed
```bash
docker run --detach -it --name pxvirt-1 --hostname pxvirt-1 \
    -p 2222:22 -p 3128:3128 -p 8006:8006 \
    --restart unless-stopped  \
    --privileged --cgroupns=private \
    --device /dev/kvm \
    -v /usr/lib/modules:/usr/lib/modules:ro \
    -v /sys/kernel/security:/sys/kernel/security \
    -v ./VM-Backup:/var/lib/vz/dump \
    -v ./ISOs:/var/lib/vz/template/iso \
    -e PASSWORD=123 \
    ghcr.io/longqt-sea/proxmox-ve-arm64
```
Replace `./ISOs` with the path to your ISO folder.

Default root password: `123`

Access the web UI at https://Docker-IP:8006 (accept the self-signed cert).
