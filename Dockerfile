# Proxmox VE 9 Container Dockerfile
#
# SPDX-License-Identifier: GPLv3 or later
# Copyright (C) 2025-2026 LongQT-sea
#
# Build:
# docker build -t proxmox-ve:latest .
#
# Run:
# docker run -d --name proxmox --hostname proxmox -p 3128:3128 -p 8006:8006 --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw -v /usr/lib/modules:/usr/lib/modules --security-opt seccomp=profile.json --restart unless-stopped proxmox-ve:latest

FROM debian:13

# Set build time variables
ARG DEBIAN_FRONTEND=noninteractive

# Set environment variables
ENV TERM="xterm-256color"

# Install base packages
RUN <<EOF
apt update
apt install -y --no-install-recommends \
    systemd \
    systemd-sysv \
    bash-completion \
    dbus \
    iproute2 \
    kmod \
    sudo \
    curl \
    wget \
    gnupg \
    ca-certificates \
    locales \
    locales-all \
    procps \
    apt-transport-https \
    e2fsprogs \
    btrfs-progs \
    nano \
    vim-tiny \
    less
locale-gen en_US.UTF-8
apt autoremove -y
apt clean
rm -rf /var/lib/apt/lists/*
EOF

# Install network packages
RUN <<EOF
apt update
apt install -y --no-install-recommends \
    iputils-ping \
    ethtool \
    traceroute \
    dnsutils \
    dnsmasq \
    isc-dhcp-client \
    wireguard-tools \
    iptables \
    bridge-utils
apt autoremove -y
apt clean
rm -rf /var/lib/apt/lists/*
EOF

# Add Proxmox VE repository
RUN <<EOF
mkdir -p /usr/share/keyrings
wget -q https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg \
    -O /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

COPY <<EOF /etc/apt/sources.list.d/pve-nosub.sources
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

# Install Proxmox VE
RUN <<EOF
apt update
apt install -y \
    proxmox-ve \
    postfix \
    open-iscsi \
    chrony \
    xfsprogs \
    pve-edk2-firmware

# Cleanup
apt remove -y os-prober || true
apt purge -y network-manager || true
apt autoremove -y
apt clean
rm -rf /var/lib/apt/lists/*
rm -f /etc/apt/sources.list.d/pve-enterprise.sources || true
rm -rf /usr/lib/modules/*
find /var/log -type f -delete
EOF

# Mask unneeded services in container
RUN <<EOF
systemctl mask \
    getty.target \
    console-getty.service \
    watchdog-mux.service || true
EOF

# Prevent pvenetcommit from overwriting /etc/network/interfaces
RUN rm -f /etc/network/interfaces.new

# Configure /etc/network/interface
COPY interfaces /etc/network/interfaces

# Config DHCP for vmbr1
COPY vmbr1.conf /etc/dnsmasq.d/vmbr1.conf

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
RUN mkdir -p /etc/systemd/journald.conf.d
COPY <<EOF /etc/systemd/journald.conf.d/container.conf
[Journal]
Storage=volatile
ForwardToSyslog=no
RuntimeMaxUse=50M
EOF

# Config OpenSSH
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Default share volumes
VOLUME "/usr/lib/modules" "/sys/fs/cgroup"

# Set working dir
WORKDIR "/root"

# Expose Proxmox VE GUI, SPICE proxy, and SSH
EXPOSE 8006/tcp
EXPOSE 3128/tcp
EXPOSE 22/tcp

# Shutdown gracefully
STOPSIGNAL SIGRTMIN+3

# Boot with systemd init
ENTRYPOINT ["/sbin/init"]

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