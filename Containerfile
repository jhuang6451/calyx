# === 基础参数 ===
ARG FEDORA_MAJOR_VERSION=44
ARG BASE_IMAGE_ORG=quay.io/fedora-ostree-desktops
ARG BASE_IMAGE_NAME=kinoite
ARG BASE_IMAGE=${BASE_IMAGE_ORG}/${BASE_IMAGE_NAME}

# NVIDIA 开关：必须是 "true" 或 "false"
ARG NVIDIA_ENABLED=false

# 资源上下文
FROM scratch AS ctx
COPY /scripts /scripts
COPY /source /source
COPY /utils /utils

# === 主构建阶段 ===
FROM ${BASE_IMAGE}:${FEDORA_MAJOR_VERSION} AS base

# 重新声明 FROM 之前的 ARG 变量，确保 Stage 内部及脚本能读取到 BASE_IMAGE_NAME
ARG BASE_IMAGE_NAME
ARG FEDORA_MAJOR_VERSION
ARG NVIDIA_ENABLED
ARG IMAGE_NAME="calyx"

ENV PATH="/tmp/bin/:${PATH}"

# 1. 运行完整镜像定制与驱动构建流水线 (单次执行，无中间层磁盘开销)
RUN --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/var \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=secret,id=GITHUB_TOKEN \
    /ctx/scripts/base/00_init.sh && \
    /ctx/scripts/base/01_packages.sh && \
    /ctx/scripts/base/02_drivers.sh && \
    /ctx/scripts/base/03_custom.sh && \
    /ctx/scripts/base/04_configs_services.sh && \
    /ctx/scripts/base/05_cleanup.sh

# 2. bootc 合规性检查
RUN --network=none \
    bootc container lint --fatal-warnings --no-truncate

CMD ["/sbin/init"]
