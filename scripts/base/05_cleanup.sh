#!/usr/bin/bash
set -eoux pipefail

echo "::group:: ===$(basename "$0")==="

# 1. 禁用所有 COPR 仓库
for i in /etc/yum.repos.d/_copr:*.repo; do
    if [[ -f "$i" ]]; then
        sed -i 's@enabled=1@enabled=0@g' "$i"
    fi
done

# 2. 禁用 RPM Fusion 仓库
for i in /etc/yum.repos.d/rpmfusion-*.repo; do
    if [[ -f "$i" ]]; then
        sed -i 's@enabled=1@enabled=0@g' "$i"
    fi
done

# 3. 禁用 fedora-coreos-pool 仓库（若存在）
if [ -f /etc/yum.repos.d/fedora-coreos-pool.repo ]; then
    sed -i 's@enabled=1@enabled=0@g' /etc/yum.repos.d/fedora-coreos-pool.repo
fi

# 4. 恢复 DNF 默认配置
dnf5 config-manager setopt keepcache=0
dnf5 versionlock clear

rm -rf /.gitkeep

# 5. 确保 Firefox 桌面快捷方式被彻底清理
rm -f /usr/share/applications/firefox*.desktop

# 6. 为 plugdev 用户组创建 sysusers 配置（满足 bootc lint 检查）
mkdir -p /usr/lib/sysusers.d
echo "g plugdev - -" > /usr/lib/sysusers.d/plugdev.conf

# 7. 清理 /var 目录（保留 cache）
find /var/* -maxdepth 0 -type d \! -name cache -exec rm -fr {} \;

# 8. 清理 /run 目录（满足 bootc lint 检查）
find /run -mindepth 1 \
  ! -path '/run/systemd' \
  ! -path '/run/systemd/resolve' \
  ! -path '/run/systemd/resolve/stub-resolv.conf' \
  ! -path '/run/secrets' \
  ! -path '/run/secrets/*' \
  ! -path '/run/.containerenv' \
  -delete 2>/dev/null || true

# 9. 清理 /tmp 临时文件
rm -rf /tmp/*
mkdir -p /var/tmp

# 10. 处理 /opt 软链接兼容性
if [[ -d /opt && -z "$(ls -A /opt 2>/dev/null)" ]]; then
    rm -rf /opt
    ln -s /var/opt /opt
fi

echo "::endgroup::"
