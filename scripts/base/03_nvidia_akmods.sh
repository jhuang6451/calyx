#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# 1. 确保 RPM Fusion Nonfree 仓库已安装
if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
    dnf5 -y install https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
fi

# 2. 安装 akmod-nvidia, 核心驱动及 kernel-devel
dnf5 -y install --setopt=install_weak_deps=False \
    akmod-nvidia \
    xorg-x11-drv-nvidia-cuda \
    xorg-x11-drv-nvidia-power \
    kernel-devel

# 3. 在构建阶段为当前内核编译 NVIDIA 模块
akmods --force

# 4. 写入 bootc 内核参数：禁用开源驱动 nouveau，并开启 Nvidia 硬件加速模式。
mkdir -p /usr/lib/bootc/kargs.d
tee /usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1", "initcall_blacklist=simpledrm_platform_driver_init"]
EOF

# 5. 写入 NVIDIA 显卡高性能与 RTD3 动态电源管理 modprobe 参数
mkdir -p /usr/lib/modprobe.d
tee /usr/lib/modprobe.d/nvidia-performance.conf <<EOF
# Enable Page Attribute Table (PAT) & fast VRAM memory allocation
options nvidia NVreg_UsePageAttributeTable=1 NVreg_InitializeSystemMemoryAllocations=0
# Enable Dynamic Power Management (RTD3) for laptops / hybrid GPUs
options nvidia NVreg_DynamicPowerManagement=0x03
EOF

if [ -f /usr/lib/systemd/system/ublue-nvidia-flatpak-runtime-sync.service ]; then
    systemctl enable ublue-nvidia-flatpak-runtime-sync.service
fi

echo "::endgroup::"
