#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# 1. 确保 RPM Fusion Nonfree 仓库已安装
if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
    dnf5 -y install https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
fi

# 2. 获取当前系统已安装内核的精确版本
KERNEL_VER=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core | head -n1)
echo "Installed kernel version: ${KERNEL_VER}"

# 3. 预建容器环境所需的目录结构
#    Containerfile 中 /var 被挂载为 tmpfs，需预先创建 RPM scriptlet 可能写入的子目录
mkdir -p /var/lib/alternatives /var/log /var/tmp /var/cache /var/lib/rpm

# 4. 下载 NVIDIA 驱动全套 RPM（包含所有依赖项）到临时目录
#    使用 dnf5 download --resolve 自动解析并下载完整依赖树
NVIDIA_RPM_DIR=/tmp/nvidia-rpms
mkdir -p "${NVIDIA_RPM_DIR}"

dnf5 download --resolve --alldeps --destdir="${NVIDIA_RPM_DIR}" \
    akmod-nvidia \
    xorg-x11-drv-nvidia-cuda

# 排除已安装的包（如 kernel-devel，已在 02_common_kernel_akmods.sh 阶段安装）
# rpm --noscripts 跳过容器内无法执行的 RPM scriptlet（setcap, audit log, dbus 等）
# --nodeps 跳过依赖检查，因为我们已通过 dnf5 download --resolve 确认了完整依赖
# --force 覆盖已存在的文件，避免与已安装包冲突
rpm -Uvh --force --nodeps --noscripts "${NVIDIA_RPM_DIR}"/*.rpm || true

# 清理下载的 RPM 包
rm -rf "${NVIDIA_RPM_DIR}"

# 5. 手动执行被 --noscripts 跳过的关键注册步骤
# 刷新共享库缓存（替代 nvidia 包的 %post ldconfig 调用）
ldconfig

# 6. 在构建阶段为当前内核编译 NVIDIA 内核模块
akmods --force --kernels "${KERNEL_VER}" || akmods --force || true

# 刷新内核模块依赖图（替代 %post depmod 调用）
depmod -a "${KERNEL_VER}" || depmod -a || true

# 7. 写入 bootc 内核参数：禁用开源驱动 nouveau，并开启 Nvidia 硬件加速模式。
mkdir -p /usr/lib/bootc/kargs.d
tee /usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1", "initcall_blacklist=simpledrm_platform_driver_init"]
EOF

# 8. 写入 NVIDIA 显卡高性能与 RTD3 动态电源管理 modprobe 参数
mkdir -p /usr/lib/modprobe.d
tee /usr/lib/modprobe.d/nvidia-performance.conf <<EOF
# Enable Page Attribute Table (PAT) & fast VRAM memory allocation
options nvidia NVreg_UsePageAttributeTable=1 NVreg_InitializeSystemMemoryAllocations=0
# Enable Dynamic Power Management (RTD3) for laptops / hybrid GPUs
options nvidia NVreg_DynamicPowerManagement=0x03
EOF

# 移除 nouveau Vulkan ICD，防止与 NVIDIA 驱动冲突
rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json

# 创建 libnvidia-ml.so 符号链接
ln -sf libnvidia-ml.so.1 /usr/lib64/libnvidia-ml.so

if [ -f /usr/lib/systemd/system/ublue-nvidia-flatpak-runtime-sync.service ]; then
    systemctl enable ublue-nvidia-flatpak-runtime-sync.service
fi

echo "::endgroup::"
