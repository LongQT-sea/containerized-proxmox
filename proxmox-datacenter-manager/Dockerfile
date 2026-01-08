# Proxmox Datacenter Manager Container Dockerfile
#
# SPDX-License-Identifier: GPLv3 or later
# Copyright (C) 2026 LongQT-sea
#
# Build:
# docker build -t proxmox-datacenter-manager .
#
# Run:
# docker run -d --name pdm --hostname pdm \
#    -p 8443:8443 -p 2222:22 \
#    --cgroupns=private \
#    --security-opt seccomp=profile.json \
#    --security-opt apparmor=unconfined \
#    --cap-add=SYS_ADMIN \
#    proxmox-datacenter-manager
#
# Set root password:
#    docker exec -it pdm passwd

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

# Add Proxmox Datacenter Manager repository
RUN <<EOF
curl -sL https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg \
    -o /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

COPY <<EOF /etc/apt/sources.list.d/pdm-no-subs.sources
Types: deb
URIs: http://download.proxmox.com/debian/pdm
Suites: trixie
Components: pdm-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

# Block unneeded packages in container
COPY <<EOF /etc/apt/preferences.d/99-pdm-unneeded-packages
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
    iproute2 \
    iputils-ping \
    sudo \
    wget \
    locales \
    procps \
    nano \
    vim-tiny \
    less \
    busybox \
    openssh-server
locale-gen en_US.UTF-8
ln -s /usr/bin/busybox /usr/bin/nslookup
ln -s /usr/bin/busybox /usr/bin/traceroute
ln -s /usr/bin/busybox /usr/bin/nc

# Install Proxmox Datacenter Manager
set -e
apt install -y \
    proxmox-datacenter-manager \
    proxmox-mail-forward \
    proxmox-offline-mirror-helper

# Cleanup
apt autoremove -y
apt clean
rm -rf /var/lib/apt/lists/*
rm /etc/apt/sources.list.d/pdm-enterprise.sources
rm /etc/machine-id
rm /var/lib/dbus/machine-id
find /var/log -type f -delete
EOF

# Mask unneeded services in container
RUN <<EOF
systemctl mask \
    getty.target \
    console-getty.service \
    systemd-udevd.service \
    systemd-modules-load.service \
    systemd-networkd-wait-online.service \
    systemd-firstboot.service \
    proc-sys-fs-binfmt_misc.automount \
    sys-kernel-config.mount \
    sys-kernel-debug.mount \
    sys-kernel-tracing.mount || true
EOF

# Config custom bash aliases
RUN <<EOF cat >> /etc/bash.bashrc

alias ls='ls --color=auto'
alias l='ls -lah'
alias ll='ls -lh'
alias la='ls -lAh'
alias cl='clear'
alias ip='ip --color'
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
RUN <<EOF
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
EOF

# Create entrypoint script
COPY <<'EOF' /entrypoint.sh
#!/bin/bash
# Remount cgroup2 as read-write (Fk docker)
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

# Expose Proxmox Datacenter Manager Web UI and SSH
EXPOSE 8443/tcp
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
LABEL org.opencontainers.image.description="Proxmox Datacenter Manager in a container"

LABEL io.containers.type="system"
LABEL io.container.runtime.privileged="true"
LABEL io.container.runtime.init="true"