# Proxmox VE 9 Container Dockerfile
#
# SPDX-License-Identifier: GPLv3 or later
# Copyright (C) 2025-2026 LongQT-sea
#
# Build:
# docker build -t proxmox-ve .
#
# Run:
# docker run -d --name pve-1 --hostname pve-1 \
#     -p 2222:22 -p 3128:3128 -p 8006:8006 \
#     --restart unless-stopped  \
#     --privileged --cgroupns=private \
#     --device /dev/kvm \
#     -v /dev/vfio:/dev/vfio \
#     -v /usr/lib/modules:/usr/lib/modules:ro \
#     -v /sys/kernel/security:/sys/kernel/security \
#     -v ./VM-Backup:/var/lib/vz/dump \
#     -v ./ISOs:/var/lib/vz/template/iso \
#     proxmox-ve
#
# Set root password:
#     docker exec -it pve-1 passwd

FROM debian:13-slim

# Set build time variables
ARG DEBIAN_FRONTEND=noninteractive

# Set environment variables
ENV TERM="xterm-256color"

# Install curl
RUN <<EOF
apt update
apt install -y --no-install-recommends \
    ca-certificates \
    curl
apt clean
rm -rf /var/lib/apt/lists/*
EOF

# Add Proxmox VE repository
RUN <<EOF
curl -sL https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg \
    -o /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

COPY <<EOF /etc/apt/sources.list.d/pve-no-subs.sources
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

# Block unneeded packages in container
COPY <<EOF /etc/apt/preferences.d/99-pve-unneeded-packages
Package: proxmox-default-kernel proxmox-kernel-* pve-firmware
Pin: release *
Pin-Priority: -1
EOF

# Install base packages
RUN <<EOF
apt update
apt install -y --no-install-recommends \
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
    cpio
locale-gen en_US.UTF-8

# Install network packages
apt install -y --no-install-recommends \
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
    bridge-utils \
    lsof

# Create dummy file for pve-manager
mkdir -p /usr/share/doc/pve-manager
touch /usr/share/doc/pve-manager/aplinfo.dat

# Install Proxmox VE
set -e
apt install -y --no-install-recommends \
    postfix \
    open-iscsi \
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
    pve-esxi-import-tools \
    proxmox-backup-restore-image \
    proxmox-offline-mirror-helper \
    pve-nvidia-vgpu-helper

# Cleanup
apt remove -y os-prober || true
apt autoremove -y
apt clean
rm -rf /var/lib/apt/lists/*
rm -f /etc/apt/sources.list.d/pve-enterprise.sources || true
rm /etc/machine-id
rm /var/lib/dbus/machine-id
find /var/log -type f -delete
EOF

# Mask unneeded services in container
RUN <<EOF
systemctl mask \
    getty.target \
    console-getty.service \
    systemd-firstboot.service \
    systemd-networkd-wait-online.service \
    watchdog-mux.service
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

# Config /etc/network/interface
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
RUN <<EOF cat >> /etc/bash.bashrc

alias ls='ls --color=auto'
alias l='ls -lah'
alias ll='ls -lh'
alias la='ls -lAh'
alias cl='clear'
alias ip='ip --color'
alias bridge='bridge -color'
alias free='free -h'
alias df='df -h'
alias du='du -hs'
EOF

# Config journald (store in RAM only)
COPY <<EOF /etc/systemd/journald.conf.d/container.conf
[Journal]
Storage=volatile
ForwardToSyslog=no
RuntimeMaxUse=50M
EOF

# Config OpenSSH
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Config LXC
RUN <<EOF
sed -i 's/^ConditionVirtualization=!container/#&/' /lib/systemd/system/lxcfs.service
cat > /etc/rc.local <<'EOF1'
#!/bin/bash
# Add loop devices for LXC
modprobe loop
for i in $(seq 0 30); do
  if [ ! -e /dev/loop$i ]; then
    mknod -m 0660 /dev/loop$i b 7 $i
  fi
done

exit 0
EOF1
chmod +x /etc/rc.local
EOF

# Create entrypoint script
COPY <<'EOF' /entrypoint.sh
#!/bin/bash
# Remount cgroup2 as read-write (F docker)
if mount | grep -q '/sys/fs/cgroup.*ro,'; then
    umount /sys/fs/cgroup
    mount -t cgroup2 cgroup2 /sys/fs/cgroup -o rw,nosuid,nodev,noexec
fi

# Boot systemd init 
exec /sbin/init
EOF
RUN chmod +x /entrypoint.sh

# Set working dir
WORKDIR "/root"

# Expose Proxmox VE GUI, SPICE proxy, and SSH
EXPOSE 8006/tcp
EXPOSE 3128/tcp
EXPOSE 22/tcp

# Shutdown gracefully
STOPSIGNAL SIGRTMIN+3

# Run with entrypoint script
ENTRYPOINT ["/entrypoint.sh"]

# Labels & Annotations
LABEL maintainer="LongQT-sea <long025733@gmail.com>"
LABEL org.opencontainers.image.os="linux"
LABEL org.opencontainers.image.architecture="amd64"
LABEL org.opencontainers.image.author="LongQT-sea <long025733@gmail.com>"
LABEL org.opencontainers.image.description="Proxmox VE in a container"

LABEL io.containers.type="system"
LABEL io.container.runtime.privileged="true"
LABEL io.container.runtime.init="true"
LABEL io.container.runtime.capabilities="ALL"
