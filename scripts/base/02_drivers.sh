#!/usr/bin/bash
set -eoux pipefail

echo "==================== [$(basename "$0")] START ===================="

# 1. 确保 RPM Fusion Free / Nonfree 仓库已安装
if ! rpm -q rpmfusion-free-release &>/dev/null; then
    dnf5 -y install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm || true
fi
if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
    dnf5 -y install https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm || true
fi

# 开启 fedora-repos-archive 仓库，确保检索到与基础镜像内核精确匹配的 kernel-devel
dnf5 config-manager setopt fedora-repos-archive.enabled=1 || true

# 2. 获取当前系统已安装内核的精确版本信息
KERNEL_VERSION=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}' kernel-core | head -n1)
KERNEL_ARCH=$(rpm -q --queryformat '%{ARCH}' kernel-core | head -n1)
FULL_KERNEL_VER="${KERNEL_VERSION}.${KERNEL_ARCH}"
echo "Target kernel version: ${FULL_KERNEL_VER}"

# 3. 预先创建 /var 与 /tmp 关键目录结构并赋予 1777 / 777 权限
mkdir -p /var/lib/alternatives /var/log/akmods /var/cache/akmods /var/tmp /tmp /var/lib/rpm /etc/cdi
chmod 1777 /tmp /var/tmp
chmod 777 /var/log/akmods /var/cache/akmods

# 4. 显式创建 akmodsbuild 用户与用户组 (防止因 tsflags=noscripts 导致降权构建时挂起)
if ! getent group akmodsbuild >/dev/null; then
    groupadd -r akmodsbuild
fi
if ! getent passwd akmodsbuild >/dev/null; then
    useradd -r -g akmodsbuild -d /var/cache/akmods -s /sbin/nologin -c "User for akmods build" akmodsbuild
fi
usermod -aG akmodsbuild root || true
chown -R akmodsbuild:akmodsbuild /var/cache/akmods /var/log/akmods || true

# 5. 安装通用内核开发包与 v4l2loopback 源码 (使用 tsflags 绕过容器 scriptlet)
dnf5 -y install \
    --setopt=install_weak_deps=False \
    --setopt=tsflags=nodocs,nocaps,nocontexts,noscripts \
    akmod-v4l2loopback \
    "kernel-devel-${KERNEL_VERSION}"

# 6. 若启用了 NVIDIA，则安装 NVIDIA 专用驱动包
if [ "${NVIDIA_ENABLED}" = "true" ]; then
    echo "Configuring NVIDIA driver and runtime..."
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo -o /etc/yum.repos.d/nvidia-container-toolkit.repo
    
    dnf5 -y install \
        --setopt=install_weak_deps=False \
        --setopt=tsflags=nodocs,nocaps,nocontexts,noscripts \
        akmod-nvidia \
        xorg-x11-drv-nvidia-cuda \
        nvidia-container-toolkit

    if command -v nvidia-ctk &>/dev/null; then
        nvidia-ctk config --set nvidia-container-cli.mode=cdi || true
    fi

    # 创建开机自动生成 CDI 配置文件的 Systemd 服务
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

    # 写入 bootc 内核参数：禁用开源驱动 nouveau，开启 Nvidia DRM 模式
    mkdir -p /usr/lib/bootc/kargs.d
    tee /usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1"]
EOF

    # 写入 NVIDIA 显卡高性能 modprobe 参数
    mkdir -p /usr/lib/modprobe.d
    tee /usr/lib/modprobe.d/nvidia-performance.conf <<EOF
# Enable Page Attribute Table (PAT) & fast VRAM memory allocation
options nvidia NVreg_UsePageAttributeTable=1 NVreg_InitializeSystemMemoryAllocations=0
EOF

    # 移除 nouveau Vulkan ICD，防止与 NVIDIA 驱动冲突
    rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json
    ln -sf libnvidia-ml.so.1 /usr/lib64/libnvidia-ml.so
fi

# 7. 在构建阶段为精确匹配的内核版本编译所有 akmods 模块 (v4l2loopback 以及 nvidia)
echo "Building akmods kernel modules for ${FULL_KERNEL_VER}..."
akmods --verbose --force --kernels "${FULL_KERNEL_VER}"

# 8. 校验已编译模块
FOUND_V4L2=$(find "/usr/lib/modules/${FULL_KERNEL_VER}" -name "v4l2loopback.ko*" 2>/dev/null || true)
if [[ -z "${FOUND_V4L2}" ]]; then
    echo "ERROR: v4l2loopback kernel module was not built!"
    cat /var/cache/akmods/v4l2loopback/*.failed.log 2>/dev/null || true
    exit 1
fi
echo "v4l2loopback verified: ${FOUND_V4L2}"

if [ "${NVIDIA_ENABLED}" = "true" ]; then
    FOUND_NVIDIA=$(find "/usr/lib/modules/${FULL_KERNEL_VER}" -name "nvidia.ko*" 2>/dev/null || true)
    if [[ -z "${FOUND_NVIDIA}" ]]; then
        echo "ERROR: NVIDIA kernel module (nvidia.ko) was not built!"
        cat /var/cache/akmods/nvidia/*.failed.log 2>/dev/null || true
        exit 1
    fi
    echo "NVIDIA kernel module verified: ${FOUND_NVIDIA}"
fi

# 9. 配置 v4l2loopback 虚拟摄像头参数与开机预加载
mkdir -p /usr/lib/modprobe.d /usr/lib/modules-load.d
tee /usr/lib/modprobe.d/v4l2loopback.conf <<EOF
options v4l2loopback devices=1 video_nr=10 card_label="Virtual Camera" exclusive_caps=1
EOF
echo "v4l2loopback" > /usr/lib/modules-load.d/v4l2loopback.conf

# 10. 刷新共享库缓存与内核模块索引
ldconfig
depmod -a "${FULL_KERNEL_VER}"

echo "==================== [$(basename "$0")] END ===================="
