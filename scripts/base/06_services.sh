#!/usr/bin/bash
echo "::group:: ===$(basename "$0")==="
set -eoux pipefail

systemctl enable tailscaled.service               # Package: tailscale
systemctl enable input-remapper.service           # Package: input-remapper

#systemctl enable rpm-ostree-countme.service       # 来自 rpm-ostree 组件，用来统计fedora活跃用户数量的机制

systemctl enable usr-share-sddm-themes.mount      # source/configs/base

systemctl disable rpm-ostreed-automatic.timer     # 来自 rpm-ostree 组件，自动更新服务

echo "::endgroup::"