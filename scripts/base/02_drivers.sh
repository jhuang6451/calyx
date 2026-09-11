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

# 2. 若启用了 NVIDIA，则安装 NVIDIA 运行时支持包与配置
if [ "${NVIDIA_ENABLED}" = "true" ]; then
    echo "Configuring NVIDIA runtime packages..."
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo -o /etc/yum.repos.d/nvidia-container-toolkit.repo
    
    dnf5 -y install \
        --setopt=install_weak_deps=False \
        --setopt=tsflags=nodocs,nocaps,nocontexts,noscripts \
        xorg-x11-drv-nvidia-cuda \
        nvidia-container-toolkit

    if command -v nvidia-ctk &>/dev/null; then
        nvidia-ctk config --set nvidia-container-cli.mode=cdi || true
    fi

    # 配置开机自动加载 NVIDIA 内核模块（确保 nvidia-uvm 及其设备节点在开机时生成）
    mkdir -p /usr/lib/modules-load.d
    tee /usr/lib/modules-load.d/nvidia.conf <<EOF
nvidia
nvidia-modeset
nvidia-uvm
nvidia-drm
EOF

    # 启用持久化守护进程以保持设备节点
    systemctl enable nvidia-persistenced.service

    # 创建开机自动生成 CDI 配置文件的 Systemd 服务
    mkdir -p /usr/lib/systemd/system
    tee /usr/lib/systemd/system/nvidia-cdi-generate.service <<EOF
[Unit]
Description=Generate NVIDIA CDI Specification for Container Runtimes (Podman/Docker)
After=multi-user.target nvidia-persistenced.service systemd-modules-load.service
Wants=nvidia-persistenced.service
ConditionPathExists=/usr/bin/nvidia-ctk

[Service]
Type=oneshot
ExecStartPre=-/usr/bin/nvidia-modprobe -u -c=0
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
    ln -sf libnvidia-ml.so.1 /usr/lib64/libnvidia-ml.so || true
fi

# 3. 配置 v4l2loopback 虚拟摄像头参数与开机预加载
mkdir -p /usr/lib/modprobe.d /usr/lib/modules-load.d
tee /usr/lib/modprobe.d/v4l2loopback.conf <<EOF
options v4l2loopback devices=1 video_nr=10 card_label="Virtual Camera" exclusive_caps=1
EOF
echo "v4l2loopback" > /usr/lib/modules-load.d/v4l2loopback.conf

echo "==================== [$(basename "$0")] END ===================="
