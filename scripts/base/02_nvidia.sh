#!/usr/bin/bash
set -eoux pipefail

echo "::group:: ===$(basename "$0")==="

# 1. 确保 RPM Fusion Nonfree 仓库已安装
if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
    dnf5 -y install https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
fi

# 开启 fedora-repos-archive 仓库，确保能够检索到与基础镜像内核精确匹配的 kernel-devel
dnf5 config-manager setopt fedora-repos-archive.enabled=1 || true

# 添加 NVIDIA Container Toolkit 官方 RPM 仓库
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo -o /etc/yum.repos.d/nvidia-container-toolkit.repo

# 2. 获取当前系统已安装内核的精确版本信息
KERNEL_VERSION=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}' kernel-core | head -n1)
KERNEL_ARCH=$(rpm -q --queryformat '%{ARCH}' kernel-core | head -n1)
FULL_KERNEL_VER="${KERNEL_VERSION}.${KERNEL_ARCH}"
echo "Target kernel version: ${FULL_KERNEL_VER}"

# 3. 预先创建 /var 与 /tmp 关键目录结构并赋予 1777 权限
mkdir -p /var/lib/alternatives /var/log/akmods /var/cache/akmods /var/tmp /tmp /var/lib/rpm /etc/cdi
chmod 1777 /tmp /var/tmp
chmod 777 /var/log/akmods /var/cache/akmods

# 4. 安装 akmod-nvidia, CUDA 支持、NVIDIA Container Toolkit 以及与当前内核完全匹配的 kernel-devel
dnf5 -y install \
    --setopt=install_weak_deps=False \
    --setopt=tsflags=nodocs,nocaps,nocontexts,noscripts \
    akmod-nvidia \
    xorg-x11-drv-nvidia-cuda \
    nvidia-container-toolkit \
    "kernel-devel-${KERNEL_VERSION}"

# 5. 配置 NVIDIA Container Toolkit 使用 CDI 模式
if command -v nvidia-ctk &>/dev/null; then
    nvidia-ctk config --set nvidia-container-cli.mode=cdi || true
fi

# 6. 在构建阶段为精确匹配的内核版本编译 NVIDIA 驱动模块
echo "Building NVIDIA kernel modules for ${FULL_KERNEL_VER}..."
akmods --force --kernels "${FULL_KERNEL_VER}"

# 7. 严苛校验：检查 nvidia.ko 内核模块文件是否构建成功
FOUND_MODULES=$(find "/usr/lib/modules/${FULL_KERNEL_VER}" -name "nvidia.ko*" 2>/dev/null || true)
if [[ -z "${FOUND_MODULES}" ]]; then
    echo "ERROR: NVIDIA kernel module (nvidia.ko) was not built!"
    echo "Checking /var/cache/akmods/nvidia/ for build log..."
    cat /var/cache/akmods/nvidia/*.failed.log 2>/dev/null || true
    exit 1
fi
echo "NVIDIA kernel module verified successfully:"
echo "${FOUND_MODULES}"

# 8. 刷新内核模块依赖关系及共享库缓存
ldconfig
depmod -a "${FULL_KERNEL_VER}"

# 9. 创建开机自动生成 CDI 配置文件的 Systemd 服务
mkdir -p /usr/lib/systemd/system
tee /usr/lib/systemd/system/nvidia-cdi-generate.service <<EOF
[Unit]
Description=Generate NVIDIA CDI Specification for Container Runtimes (Podman/Docker)
After=multi-user.target
ConditionPathExists=/usr/bin/nvidia-ctk

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# 10. 写入 bootc 内核参数：禁用开源驱动 nouveau，开启 Nvidia DRM 模式
mkdir -p /usr/lib/bootc/kargs.d
tee /usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1"]
EOF

# 11. 写入 NVIDIA 显卡高性能 modprobe 参数
mkdir -p /usr/lib/modprobe.d
tee /usr/lib/modprobe.d/nvidia-performance.conf <<EOF
# Enable Page Attribute Table (PAT) & fast VRAM memory allocation
options nvidia NVreg_UsePageAttributeTable=1 NVreg_InitializeSystemMemoryAllocations=0
EOF

# 移除 nouveau Vulkan ICD，防止与 NVIDIA 驱动冲突
rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json

# 创建 libnvidia-ml.so 符号链接
ln -sf libnvidia-ml.so.1 /usr/lib64/libnvidia-ml.so

echo "::endgroup::"
