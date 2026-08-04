#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# 1. 确保 RPM Fusion Nonfree 仓库已安装
if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
    dnf5 -y install https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
fi

# 开启 fedora-repos-archive 仓库，确保能够检索到与基础镜像内核精确匹配的 kernel-devel
dnf5 config-manager setopt fedora-repos-archive.enabled=1 || true

# 清理 versionlock，解除对 32 位 multilib (i686) 依赖库的排除限制
dnf5 versionlock clear || true

# 2. 获取当前系统已安装内核的精确版本
KERNEL_VER=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}' kernel-core | head -n1)
echo "Installed kernel-core version: ${KERNEL_VER}"

# 3. 预建容器环境所需的目录结构
#    在 Containerfile 中 /var 被挂载为 tmpfs，RPM scriptlet 尝试写入 /var 子目录时会失败。
#    预先创建这些目录以避免 scriptlet 报错导致整个事务回滚。
mkdir -p /var/lib/alternatives /var/log /var/tmp /var/cache /var/lib/rpm

# 4. 安装核心 NVIDIA 驱动及对应版本的 kernel-devel
#    排除 nvidia-settings (GUI 配置面板)，其 %posttrans 脚本依赖 update-desktop-database
#    等桌面工具，在容器构建环境中会导致 RPM 事务失败。
dnf5 -y install \
    --setopt=install_weak_deps=False \
    --exclude=nvidia-settings \
    akmod-nvidia \
    xorg-x11-drv-nvidia-cuda \
    "kernel-devel-${KERNEL_VER}"

# 5. 单独安装 nvidia-settings，允许 scriptlet 失败
dnf5 -y install --setopt=install_weak_deps=False nvidia-settings || \
    rpm -ivh --nodeps --noscripts \
        $(dnf5 download --destdir=/tmp nvidia-settings 2>/dev/null && echo /tmp/nvidia-settings-*.rpm) || true

# 6. 刷新共享库缓存与内核模块依赖
ldconfig
depmod -a "${KERNEL_VER}.$(uname -m)" 2>/dev/null || depmod -a || true

# 7. 在构建阶段为当前内核编译 NVIDIA 模块
akmods --force

# 再次刷新 depmod 以注册新编译的 nvidia 模块
depmod -a "${KERNEL_VER}.$(uname -m)" 2>/dev/null || depmod -a || true

# 8. 写入 bootc 内核参数：禁用开源驱动 nouveau，并开启 Nvidia 硬件加速模式。
mkdir -p /usr/lib/bootc/kargs.d
tee /usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1", "initcall_blacklist=simpledrm_platform_driver_init"]
EOF

# 9. 写入 NVIDIA 显卡高性能与 RTD3 动态电源管理 modprobe 参数
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
