# === 基础参数 ===
ARG FEDORA_MAJOR_VERSION=44
ARG BASE_IMAGE_ORG=quay.io/fedora-ostree-desktops
ARG BASE_IMAGE_NAME=kinoite
ARG BASE_IMAGE=${BASE_IMAGE_ORG}/${BASE_IMAGE_NAME}
ARG REGISTRY=registry.elix1r.top
ARG KERNEL_VERSION

# 1. 引入匹配锁定的内核驱动镜像 (动态多阶段引用)
FROM ${REGISTRY}/calyx-kmods:${KERNEL_VERSION} AS kmods

# 2. 资源上下文 (纯净源码与脚本)
FROM scratch AS ctx
COPY /scripts /scripts
COPY /source /source
COPY /utils /utils

# === 主构建阶段 ===
FROM ${BASE_IMAGE}:${FEDORA_MAJOR_VERSION} AS base

# 重新声明 FROM 之前的 ARG 变量，确保 Stage 内部及脚本能读取
ARG BASE_IMAGE_NAME
ARG FEDORA_MAJOR_VERSION
ARG NVIDIA_ENABLED=false
ARG IMAGE_NAME="calyx"
ARG KERNEL_VERSION

ENV PATH="/tmp/bin/:${PATH}"

# 从 kmods 复制对应内核的驱动模块
COPY --from=kmods /modules/${KERNEL_VERSION}/extra /usr/lib/modules/${KERNEL_VERSION}/extra
# 从 kmods 复制工具与库 (ntfsprogs-plus 用户态工具与动态库)
COPY --from=kmods /tools/bin/ /usr/bin/
COPY --from=kmods /tools/sbin/ /usr/sbin/
COPY --from=kmods /tools/lib64/ /usr/lib64/

# 运行完整镜像定制与驱动配置流水线 (单次执行，无中间层磁盘开销)
RUN --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/var \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    KERNEL_VERSION="${KERNEL_VERSION}" \
    NVIDIA_ENABLED="${NVIDIA_ENABLED}" \
    FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION}" \
    /ctx/scripts/base/00_init.sh && \
    /ctx/scripts/base/01_packages.sh && \
    /ctx/scripts/base/02_drivers.sh && \
    /ctx/scripts/base/03_custom.sh && \
    /ctx/scripts/base/04_configs_services.sh && \
    /ctx/scripts/base/05_cleanup.sh

# bootc 合规性检查
RUN --network=none \
    bootc container lint --fatal-warnings --no-truncate

CMD ["/sbin/init"]
