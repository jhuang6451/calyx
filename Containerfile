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

# 1. 基础环境初始化与系统软件包安装 (极少变动，体积最大，单独成层缓存)
RUN --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/var \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=secret,id=GITHUB_TOKEN \
    /ctx/scripts/base/00_init.sh && \
    /ctx/scripts/base/01_packages.sh

# 2. NVIDIA 驱动及内核模块编译 (耗时长，独立成层缓存)
RUN --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/var \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=secret,id=GITHUB_TOKEN \
    if [ "${NVIDIA_ENABLED}" = "true" ]; then \
        /ctx/scripts/base/02_nvidia.sh; \
    else \
        echo "NVIDIA disabled, skipping..."; \
    fi

# 3. 增强定制组件与实用工具 (Starship, Nerd Fonts, Mihomo Party 等)
RUN --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/var \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=secret,id=GITHUB_TOKEN \
    /ctx/scripts/base/03_custom.sh

# 4. 系统配置文件覆盖、服务管理与构建清理 (最常修改，放最底层，构建秒级完成)
RUN --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/var \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=secret,id=GITHUB_TOKEN \
    /ctx/scripts/base/04_configs_services.sh && \
    /ctx/scripts/base/05_cleanup.sh

# 5. bootc 合规性检查
RUN --network=none \
    bootc container lint --fatal-warnings --no-truncate

CMD ["/sbin/init"]
