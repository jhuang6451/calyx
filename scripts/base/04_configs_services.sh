#!/usr/bin/bash
set -eoux pipefail

echo "==================== [$(basename "$0")] START ===================="

# 1. 同步仓库中的基础配置覆盖到根文件系统
echo "Applying base configuration overrides..."
rsync -rvKl /ctx/source/configs/base/ /

# 为容器内安装的每个内核版本生成模块依赖关系（在 CI 容器环境中不能直接执行无参数的 depmod -a，因为 uname -r 返回的是宿主机内核）
for kdir in /usr/lib/modules/*; do
    if [ -d "$kdir" ]; then
        kver=$(basename "$kdir")
        echo "Updating module dependencies for ${kver}..."
        depmod -a "${kver}"
    fi
done

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

# 5. 确保 SSH 配置目录及文件权限合规
chmod 0755 /etc/ssh/sshd_config.d 2>/dev/null || true
chmod 0644 /etc/ssh/sshd_config.d/* 2>/dev/null || true

echo "==================== [$(basename "$0")] END ===================="
