#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

IMAGE_NAME="${BASE_IMAGE_NAME}" AKMODNV_PATH="/tmp/rpms/nvidia" MULTILIB=0 /tmp/rpms/nvidia/ublue-os/nvidia-install.sh
rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json
ln -sf libnvidia-ml.so.1 /usr/lib64/libnvidia-ml.so
# 写入 bootc 内核参数：禁用开源驱动 nouveau，并开启 Nvidia 硬件加速模式。
tee /usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1", "initcall_blacklist=simpledrm_platform_driver_init"]
EOF

if [[ -d /ctx/system_files/nvidia && -n "$(ls -A /ctx/system_files/nvidia 2>/dev/null)" ]]; then
    rsync -rvKl /ctx/system_files/nvidia/ /
fi
systemctl enable ublue-nvidia-flatpak-runtime-sync.service

echo "::endgroup::"
