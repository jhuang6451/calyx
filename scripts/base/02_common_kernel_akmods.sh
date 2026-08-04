#!/usr/bin/bash
echo "::group:: ===$(basename "$0")==="
set -eoux pipefail

# 跳过对官方内核的修改，直接使用 Fedora 官方最新内核
echo "Using Fedora official kernel, skipping kernel replacement."

# 安装 RPM Fusion Free 仓库（用于获取 akmod-v4l2loopback 等硬件扩展模块）
if ! rpm -q rpmfusion-free-release &>/dev/null; then
    dnf5 -y install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm || true
fi

# 安装 akmod-v4l2loopback 扩展模块
dnf5 -y install --setopt=install_weak_deps=False akmod-v4l2loopback || true

echo "::endgroup::"