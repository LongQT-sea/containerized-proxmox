# Proxmox VE / PXVIRT Multi-Arch Container Dockerfile
#
# SPDX-License-Identifier: GPLv3 or later
# Copyright (C) 2025-2026 LongQT-sea
#
# Build:
# docker build -t proxmox-ve .
#
# Run:
# docker run -dit --name pve-1 --hostname pve-1 \
#     -p 2222:22 -p 3128:3128 -p 8006:8006 \
#     --restart unless-stopped  \
#     --cgroupns=private \
#     --security-opt seccomp=profile.json \
#     --security-opt apparmor=unconfined \
#     --security-opt systempaths=unconfined \
#     --device-cgroup-rule='a *:* rwm' \
#     --cap-add=SYS_ADMIN \
#     --cap-add=NET_ADMIN \
#     --cap-add=MAC_ADMIN \
#     --cap-add=SYS_MODULE \
#     --cap-add=IPC_LOCK \
#     --cap-add=SYS_PTRACE \
#     -v /dev/vfio:/dev/vfio \
#     -v /usr/lib/modules:/usr/lib/modules:ro \
#     -v /sys/kernel/security:/sys/kernel/security \
#     -v ./VM-Backup:/var/lib/vz/dump \
#     -v ./ISOs:/var/lib/vz/template/iso \
#     -e PASSWORD=123 \
#     proxmox-ve

# Select base image
FROM --platform=linux/amd64 debian:13-slim AS base-amd64
FROM --platform=linux/arm64 debian:12-slim AS base-arm64

FROM base-${TARGETARCH} AS base

# Build-time variables
ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH

ENV TERM="xterm-256color"

# Install curl
RUN <<EOF
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

# Add repository
RUN <<EOF
set -e

if [ "${TARGETARCH}" = "amd64" ]; then
    KEY_URL="https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg"
    KEY_PATH="/usr/share/keyrings/proxmox-archive-keyring.gpg"
    URI="http://download.proxmox.com/debian/pve"
    SUITE="trixie"
    COMPONENT="pve-no-subscription"
elif [ "${TARGETARCH}" = "arm64" ]; then
    KEY_URL="https://mirrors.lierfang.com/pxcloud/lierfang.gpg"
    KEY_PATH="/etc/apt/trusted.gpg.d/lierfang.gpg"
    URI="https://mirrors.lierfang.com/pxcloud/pxvirt"
    SUITE="bookworm"
    COMPONENT="main"
fi

curl -sL "${KEY_URL}" -o "${KEY_PATH}"

cat > /etc/apt/sources.list.d/pve.sources <<SOURCES
Types: deb
URIs: ${URI}
Suites: ${SUITE}
Components: ${COMPONENT}
Signed-By: ${KEY_PATH}
SOURCES
EOF

# Block unneeded packages in container
COPY <<EOF /etc/apt/preferences.d/99-pve-unneeded-packages
Package: proxmox-default-kernel proxmox-kernel-* pve-firmware
Pin: release *
Pin-Priority: -1
EOF

# Install base packages
RUN <<EOF
apt-get update
apt-get install -y --no-install-recommends \
    systemd-sysv \
    bash-completion \
    dbus \
    kmod \
    sudo \
    wget \
    gnupg \
    locales \
    procps \
    apt-transport-https \
    e2fsprogs \
    btrfs-progs \
    ntfs-3g \
    nano \
    vim-tiny \
    less \
    openssh-server \
    whiptail \
    cpio \
    usbutils
locale-gen en_US.UTF-8

# Install network packages
apt-get install -y --no-install-recommends \
    iputils-ping \
    ifupdown2 \
    iproute2 \
    ethtool \
    traceroute \
    dnsutils \
    dnsmasq \
    isc-dhcp-client \
    wireguard-tools \
    iptables \
    lsof

# Create dummy file for pve-manager
mkdir -p /usr/share/doc/pve-manager
touch /usr/share/doc/pve-manager/aplinfo.dat

# Install Proxmox VE / PXVIRT
set -e
apt-get install -y --no-install-recommends \
    postfix \
    xfsprogs \
    zfs-zed \
    numactl \
    virtiofsd \
    skopeo \
    ssl-cert \
    groff-base \
    samba-common-bin \
    pve-manager \
    pve-edk2-firmware \
    proxmox-firewall \
    proxmox-backup-restore-image \
    proxmox-offline-mirror-helper

if [ "$TARGETARCH" = "amd64" ]; then
    apt-get install -y --no-install-recommends \
        open-iscsi \
        pve-esxi-import-tools \
        pve-nvidia-vgpu-helper
fi

# Cleanup
apt-get remove -y os-prober || true
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -f /etc/apt/sources.list.d/pve-enterprise.sources  || true
rm -f /etc/machine-id
rm -f /var/lib/dbus/machine-id
find /var/log -type f -delete
EOF

# Mask unneeded services
RUN <<EOF
systemctl mask \
    systemd-networkd-wait-online.service \
    watchdog-mux.service
EOF

# Add keyring for pveam
RUN <<EOF
gpg --keyserver keyserver.ubuntu.com --recv-keys \
    A7BCD1420BFE778E \
    85C25E95A16EB94D \
    39DE63C7D57A32124785E63DB859507D6B1F46D3

gpg --export \
    A7BCD1420BFE778E \
    85C25E95A16EB94D \
    39DE63C7D57A32124785E63DB859507D6B1F46D3 \
    > /usr/share/doc/pve-manager/trustedkeys.gpg
rm -rf /root/.gnupg
EOF

# Prevent Docker DNS NAT rules from being flushed when using user-defined bridge
RUN systemctl mask nftables.service

# Prevent pvenetcommit from overwriting /etc/network/interfaces
RUN rm -f /etc/network/interfaces.new

# No longer require restart after first boot
RUN <<EOF
update-alternatives --set iptables /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
update-alternatives --set ebtables /usr/sbin/ebtables-legacy
EOF

# Config /etc/network/interfaces
COPY <<EOF /etc/network/interfaces
auto lo
iface lo inet loopback

# Docker/Podman managed this interface
iface eth0 inet manual

# NAT bridge for VMs if vmbr2 not connected to physical LAN network
auto vmbr1
iface vmbr1 inet static
        address 172.16.99.1/24
        bridge-ports none
        bridge-stp off
        bridge-fd 0

        # Enable IPv4 forward and NAT
        up    sysctl -w net.ipv4.ip_forward=1
        up    iptables -t nat -A POSTROUTING -s 172.16.99.0/24 ! -d 172.16.99.0/24 -j MASQUERADE

        # Prevent DNS leaks
        up    iptables -t nat -A PREROUTING -i vmbr1 -p udp --dport 53 -j REDIRECT --to-ports 53
        up    iptables -t nat -A PREROUTING -i vmbr1 -p tcp --dport 53 -j REDIRECT --to-ports 53

iface vmbr1 inet6 static
        address dead:beef::1/64

        # Enable IPv6 forward and NAT6
        up    sysctl -w net.ipv6.conf.all.forwarding=1
        up    ip6tables -t nat -A POSTROUTING -s dead:beef::/64 ! -d dead:beef::/64 -j MASQUERADE

        # Prevent DNS leaks
        up    ip6tables -t nat -A PREROUTING -i vmbr1 -p udp --dport 53 -j REDIRECT --to-ports 53
        up    ip6tables -t nat -A PREROUTING -i vmbr1 -p tcp --dport 53 -j REDIRECT --to-ports 53

# Empty bridge, replace 'none' with macvlan, veth or physical interface to connect to physical LAN if needed
auto vmbr2
iface vmbr2 inet static
        bridge-ports none
        bridge-stp off
        bridge-fd 0

source /etc/network/interfaces.d/*
EOF

# Config DHCP for vmbr1 bridge
COPY <<EOF /etc/dnsmasq.d/vmbr1.conf
# Dnsmasq configuration for vmbr1 NAT network

# Don't read /etc/resolv.conf, use servers defined below
no-resolv

# Use Adguard DNS server
server=94.140.14.14
server=94.140.15.15
server=2a10:50c0::ad1:ff
server=2a10:50c0::ad2:ff

# Listen only on vmbr1
interface=vmbr1
except-interface=lo
bind-interfaces

# Enable IPv6 RA
enable-ra

# Enable IPv6 SLAAC
dhcp-range=tag:vmbr1,::1,constructor:vmbr1,ra-names,12h

# IPv4 DHCP range
dhcp-range=set:vmbr1,172.16.99.10,172.16.99.199,255.255.255.0,12h

# Domain configuration
expand-hosts
domain=lab,172.16.99.0/24
local=/lab/
local=/lan/

# DHCP settings
dhcp-lease-max=200
cache-size=200
no-negcache
dhcp-authoritative

# Windows compatibility
dhcp-option=252,"\n"
dhcp-option=vendor:MSFT,2,1i

# Security
dhcp-name-match=set:wpad-ignore,wpad
dhcp-ignore-names=tag:wpad-ignore
domain-needed
bogus-priv
localise-queries

# RFC6761 configuration
server=/bind/
server=/invalid/
server=/local/
server=/localhost/
server=/onion/
server=/test/
EOF

# Config custom bash aliases
RUN cat >> /etc/bash.bashrc <<'EOF'

alias ls='ls --color=auto'
alias l='ls -lah'
alias ll='ls -lh'
alias la='ls -lAh'
alias cl='clear'
alias ip='ip --color'
alias bridge='bridge -color'
alias free='free -h'
alias df='df -h'
alias dus='du -hxs'
alias dux='du -hxd1'
EOF

# Config journald (store in RAM only)
RUN mkdir -p /etc/systemd/journald.conf.d
COPY <<EOF /etc/systemd/journald.conf.d/container.conf
[Journal]
Storage=volatile
ForwardToSyslog=no
RuntimeMaxUse=50M
EOF

# Config OpenSSH
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# # Config LXC
RUN <<EOF
sed -i 's/^ConditionVirtualization=!container/#&/' /lib/systemd/system/lxcfs.service
cat > /etc/rc.local <<'RCLOCAL'
#!/bin/bash
# Add loop devices for LXC
modprobe loop
for i in $(seq 0 30); do
  if [ ! -e /dev/loop$i ]; then
    mknod -m 0660 /dev/loop$i b 7 $i
  fi
done

# Unmask after boot to fix LXC startup issues (masked earlier in entrypoint script)
umount /sys/class/drm
RCLOCAL

if [ "$TARGETARCH" = "arm64" ]; then
cat >> /etc/rc.local <<'RCLOCAL_ARM'

# Update arm64 LXC template
pveam update 2>/dev/null

# Remove unsupported amd64 turnkeylinux repo
rm -f /var/lib/pve-manager/apl-info/releases.turnkeylinux.org
RCLOCAL_ARM
fi

echo "" >> /etc/rc.local
echo "exit 0" >> /etc/rc.local
chmod +x /etc/rc.local
EOF

# Create entrypoint script
COPY <<'EOF' /entrypoint.sh
#!/bin/bash
# Remount these as read-write (F docker)
mount -o remount,rw /sys/fs/cgroup 2>/dev/null
mount -o remount,rw /proc/sys 2>/dev/null
mount -o remount,rw /sys 2>/dev/null

# Prevent udev from touching the host GPU during early boot to avoid black screens in the host DE
mount -t tmpfs -o ro,noexec,nosuid tmpfs /sys/class/drm

# Set shm size to 1G to prevent cluster joining issue
mount -o remount,size=1G /dev/shm

# Add device nodes needed by PVE
mkdir -p /dev/net /dev/mapper
mknod /dev/kvm            c 10 232
mknod /dev/fuse           c 10 229
mknod /dev/zfs            c 10 249
mknod /dev/net/tun        c 10 200
mknod /dev/loop-control   c 10 237
mknod /dev/mapper/control c 10 236
chown root:kvm  /dev/kvm
chown root:disk /dev/loop-control
chmod 666 /dev/kvm /dev/zfs
chmod 660 /dev/loop-control
chmod 600 /dev/mapper/control

# Set root password on first boot
if [ -n "$PASSWORD" ] && [ ! -f /etc/machine-id ]; then
    echo "root:$PASSWORD" | chpasswd
fi

exec "$@"
EOF
RUN chmod +x /entrypoint.sh

# Run with custom entrypoint script
ENTRYPOINT ["/entrypoint.sh"]

# Default command
CMD ["/sbin/init", "--log-target=console", "--log-level=info"]

WORKDIR "/root"

# Expose Proxmox VE GUI, SPICE proxy, and SSH
EXPOSE 8006/tcp
EXPOSE 3128/tcp
EXPOSE 22/tcp

# Shutdown gracefully
STOPSIGNAL SIGRTMIN+3

# Labels & Annotations
LABEL maintainer="LongQT-sea <long025733@gmail.com>"
LABEL org.opencontainers.image.os="linux"
LABEL org.opencontainers.image.architecture="${TARGETARCH}"
LABEL org.opencontainers.image.author="LongQT-sea <long025733@gmail.com>"
LABEL org.opencontainers.image.description="Proxmox VE / PXVIRT multi-arch container"

LABEL io.containers.type="system"
LABEL io.container.runtime.init="true"
LABEL io.container.runtime.capabilities="ALL"

