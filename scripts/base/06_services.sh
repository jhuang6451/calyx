#!/usr/bin/bash
echo "::group:: ===$(basename "$0")==="
set -eoux pipefail

systemctl enable tailscaled.service               # Package: tailscale
systemctl enable input-remapper.service           # Package: input-remapper
systemctl enable sshd.socket                      # OpenSSH 按需连接 Socket 服务

# 确保 SSH 配置及公钥文件权限安全
chmod 0755 /etc/ssh/sshd_config.d /etc/ssh/authorized_keys.d || true
chmod 0644 /etc/ssh/sshd_config.d/* /etc/ssh/authorized_keys.d/* || true
if [ -d /etc/skel/.ssh ]; then
    chmod 0700 /etc/skel/.ssh
    chmod 0600 /etc/skel/.ssh/authorized_keys || true
fi

#systemctl enable rpm-ostree-countme.service       # 来自 rpm-ostree 组件，用来统计fedora活跃用户数量的机制

systemctl enable usr-share-sddm-themes.mount      # source/configs/base

systemctl disable rpm-ostreed-automatic.timer     # 来自 rpm-ostree 组件，自动更新服务

echo "::endgroup::"