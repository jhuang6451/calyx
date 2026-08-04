#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# 1. 确保 RPM Fusion Nonfree 仓库已安装
if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
    dnf5 -y install https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
fi

# 开启 fedora-repos-archive 仓库，确保能够检索到与基础镜像内核精确匹配的 kernel-devel
dnf5 config-manager setopt fedora-repos-archive.enabled=1 || true

# 2. 获取当前系统已安装内核的精确版本信息
KERNEL_VERSION=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}' kernel-core | head -n1)
KERNEL_ARCH=$(rpm -q --queryformat '%{ARCH}' kernel-core | head -n1)
FULL_KERNEL_VER="${KERNEL_VERSION}.${KERNEL_ARCH}"
echo "Target kernel version: ${FULL_KERNEL_VER}"

# 3. 预先创建 /var 关键目录结构
mkdir -p /var/lib/alternatives /var/log /var/tmp /var/cache /var/lib/rpm

# 4. 安装 akmod-nvidia, CUDA 支持以及与当前内核完全匹配的 kernel-devel
#    使用 tsflags=noscripts 避免 akmod-nvidia 的 %post 脚本因 root 用户运行抛出 ERROR: Not to be used as root 导致事务中断
dnf5 -y install \
    --setopt=install_weak_deps=False \
    --setopt=tsflags=nodocs,nocaps,nocontexts,noscripts \
    akmod-nvidia \
    xorg-x11-drv-nvidia-cuda \
    "kernel-devel-${KERNEL_VERSION}"

# 5. 在构建阶段为精确匹配的内核版本编译 NVIDIA 驱动模块
echo "Building NVIDIA kernel modules for ${FULL_KERNEL_VER}..."
akmods --force --kernels "${FULL_KERNEL_VER}"

# 6. 严苛校验：检查 nvidia.ko 内核模块文件是否构建成功
FOUND_MODULES=$(find "/usr/lib/modules/${FULL_KERNEL_VER}" -name "nvidia.ko*" 2>/dev/null || true)
if [[ -z "${FOUND_MODULES}" ]]; then
    echo "ERROR: NVIDIA kernel module (nvidia.ko) was not built!"
    echo "Checking /var/cache/akmods/nvidia/ for build log..."
    cat /var/cache/akmods/nvidia/*.failed.log 2>/dev/null || true
    exit 1
fi
echo "NVIDIA kernel module verified successfully:"
echo "${FOUND_MODULES}"

# 7. 刷新内核模块依赖关系及共享库缓存
ldconfig
depmod -a "${FULL_KERNEL_VER}"

# 8. 写入 bootc 内核参数：禁用开源驱动 nouveau，开启 Nvidia DRM 模式
mkdir -p /usr/lib/bootc/kargs.d
tee /usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1"]
EOF

# 9. 写入 NVIDIA 显卡高性能 modprobe 参数（保持桌面卡及笔记本硬件兼容性）
mkdir -p /usr/lib/modprobe.d
tee /usr/lib/modprobe.d/nvidia-performance.conf <<EOF
# Enable Page Attribute Table (PAT) & fast VRAM memory allocation
options nvidia NVreg_UsePageAttributeTable=1 NVreg_InitializeSystemMemoryAllocations=0
EOF

# 移除 nouveau Vulkan ICD，防止与 NVIDIA 驱动冲突
rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json

# 创建 libnvidia-ml.so 符号链接
ln -sf libnvidia-ml.so.1 /usr/lib64/libnvidia-ml.so

if [ -f /usr/lib/systemd/system/ublue-nvidia-flatpak-runtime-sync.service ]; then
    systemctl enable ublue-nvidia-flatpak-runtime-sync.service
fi

echo "::endgroup::"
