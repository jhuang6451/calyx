#!/usr/bin/bash
echo "::group:: ===$(basename "$0")==="
set -eoux pipefail

# 调查建议：推荐切换至 AI/ML SIG 提供的包，其对 Podman 的 SELinux 策略和 CDI 支持更佳。
# 实施方法：启用 copr: @ai-ml/nvidia-container-toolkit 后安装 nvidia-container-toolkit。
# dnf config-manager setopt excludepkgs=golang-github-nvidia-container-toolkit



# 集成建议：可在此处通过 copr_install_isolated 安装 AI/ML SIG 的工具包，
# 并运行 nvidia-ctk cdi generate 自动生成配置文件，实现 Podman 开箱即用 GPU。
IMAGE_NAME="${BASE_IMAGE_NAME}" AKMODNV_PATH="/tmp/rpms/nvidia" MULTILIB=0 /tmp/rpms/nvidia/ublue-os/nvidia-install.sh
rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json
ln -sf libnvidia-ml.so.1 /usr/lib64/libnvidia-ml.so
# 写入 bootc 内核参数：禁用开源驱动 nouveau，并开启 Nvidia 硬件加速模式。
tee /usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1", "initcall_blacklist=simpledrm_platform_driver_init"]
EOF

rsync -rvKl /ctx/system_files/nvidia/ /
systemctl enable ublue-nvidia-flatpak-runtime-sync.service

echo "::endgroup::"
