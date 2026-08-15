#!/usr/bin/bash
set -eoux pipefail

echo "::group:: ===$(basename "$0")==="

# 1. 同步仓库中的基础配置覆盖到根文件系统
echo "Applying base configuration overrides..."
rsync -rvKl /ctx/source/configs/base/ /

# 2. 配置 Flathub 软件源并屏蔽 Fedora 官方 Flatpak 源
mkdir -p /etc/flatpak/remotes.d/
curl --retry 3 -Lo /etc/flatpak/remotes.d/flathub.flatpakrepo https://dl.flathub.org/repo/flathub.flatpakrepo

# 3. 启用系统核心服务与 Socket
systemctl enable tailscaled.service               # Package: tailscale
systemctl enable input-remapper.service           # Package: input-remapper
systemctl enable sshd.socket                      # OpenSSH 按需连接 Socket 服务
systemctl enable usr-share-sddm-themes.mount      # source/configs/base
systemctl enable flatpak-nuke-fedora.service      # source/configs/base

if [ -f /usr/lib/systemd/system/ublue-nvidia-flatpak-runtime-sync.service ]; then
    systemctl enable ublue-nvidia-flatpak-runtime-sync.service
fi

if [ -f /usr/lib/systemd/system/nvidia-cdi-generate.service ]; then
    systemctl enable nvidia-cdi-generate.service
fi

# 4. 禁用/屏蔽冗余服务
systemctl disable rpm-ostreed-automatic.timer
systemctl disable flatpak-add-fedora-repos.service
systemctl mask flatpak-add-fedora-repos.service
rm -f /usr/lib/systemd/system/flatpak-add-fedora-repos.service

# 5. 确保 SSH 配置及公钥文件具有合规严格的安全权限
chmod 0755 /etc/ssh/sshd_config.d /etc/ssh/authorized_keys.d 2>/dev/null || true
chmod 0644 /etc/ssh/sshd_config.d/* /etc/ssh/authorized_keys.d/* 2>/dev/null || true
if [ -d /etc/skel/.ssh ]; then
    chmod 0700 /etc/skel/.ssh
    chmod 0600 /etc/skel/.ssh/authorized_keys 2>/dev/null || true
fi

echo "::endgroup::"
