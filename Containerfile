# === 基础参数 ===
ARG FEDORA_MAJOR_VERSION=43
ARG KERNEL=6.12.11-200.fc41.x86_64
ARG AKMODS_FLAVOR=main
ARG BASE_IMAGE_ORG=quay.io/fedora-ostree-desktops
ARG BASE_IMAGE_NAME=kinoite
ARG BASE_IMAGE=${BASE_IMAGE_ORG}/${BASE_IMAGE_NAME}

# NVIDIA 开关：必须是 "true" 或 "false"
ARG NVIDIA_ENABLED=false

# === 多阶段准备 ===
FROM ghcr.io/ublue-os/akmods:${AKMODS_FLAVOR}-${FEDORA_MAJOR_VERSION}-${KERNEL} AS akmods

# NVIDIA 分支逻辑
FROM scratch AS nvidia-false
FROM ghcr.io/ublue-os/akmods-nvidia-open:${AKMODS_FLAVOR}-${FEDORA_MAJOR_VERSION}-${KERNEL} AS nvidia-true

# 根据 ARG 选择来源
FROM nvidia-${NVIDIA_ENABLED} AS nvidia-provider

# 资源上下文
FROM scratch AS ctx
COPY /scripts /scripts
COPY /source /source
COPY /utils /utils

# === 主构建阶段 ===
FROM ${BASE_IMAGE}:${FEDORA_MAJOR_VERSION} AS base

ARG FEDORA_MAJOR_VERSION
ARG KERNEL
ARG NVIDIA_ENABLED

ENV PATH="/tmp/bin/:${PATH}"

# 1. 基础安装
RUN --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/var \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=bind,from=akmods,src=/kernel-rpms,dst=/tmp/kernel-rpms \
    --mount=type=bind,from=akmods,src=/rpms/common,dst=/tmp/rpms/common \
    --mount=type=bind,from=akmods,src=/rpms/kmods,dst=/tmp/rpms/kmods \
    /ctx/scripts/base/00_init.sh && \
    /ctx/scripts/base/01_packages.sh && \
    /ctx/scripts/base/02_common_kernel_akmods.sh

# 2. NVIDIA 安装
RUN --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/var \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=bind,from=nvidia-provider,src=/rpms,dst=/tmp/rpms/nvidia \
    --mount=type=bind,from=nvidia-provider,src=/system_files,dst=/ctx/system_files/nvidia \
    if [ "${NVIDIA_ENABLED}" = "true" ]; then \
        /ctx/scripts/base/03_nvidia_akmods.sh; \
    else \
        echo "NVIDIA disabled, skipping..."; \
    fi

# 3. 后期配置与清理
RUN --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/var \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    /ctx/scripts/base/04_hotfix.sh && \
    /ctx/scripts/base/05_custom.sh && \
    /ctx/scripts/base/06_services.sh && \
    /ctx/scripts/base/07_flatpak.sh && \
    /ctx/scripts/base/08_cleanup.sh

CMD ["/sbin/init"]
