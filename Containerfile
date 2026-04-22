# === 环境变量与构建参数说明 ===
# 以下变量控制镜像的构建行为，通常由 Justfile 通过 --build-arg 动态传入：
# 1. BASE_IMAGE_ORG/NAME: 基础镜像的来源组织与名称 (默认 Fedora Kinoite)。
# 2. FEDORA_MAJOR_VERSION: Fedora 主版本号，决定了软件仓库的版本。
# 3. AKMODS_FLAVOR: 驱动版本策略。main(开发版/前沿), coreos-stable(稳定版)。
# 4. KERNEL: 确切的内核版本号，确保驱动与内核严格匹配。
# 5. IMAGE_NAME/VENDOR: 最终镜像的名称与所有者标识。
# 6. IMAGE_TAG: 镜像标签。
# 7. SHA_HEAD_SHORT/VERSION: 用于镜像元数据标记的 Git 哈希与版本字符串。

ARG BASE_IMAGE_ORG="${BASE_IMAGE_ORG}:-quay.io/fedora-ostree-desktops"
ARG BASE_IMAGE_NAME="${BASE_IMAGE_NAME}:-kinoite"
ARG BASE_IMAGE="${BASE_IMAGE_ORG}/${BASE_IMAGE_NAME}"

ARG FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION}:-43"
ARG KERNEL="${KERNEL}:-6.17.12-300.fc43.x86_64"

ARG AKMODS_FLAVOR="${AKMODS_FLAVOR}-${FEDORA_MAJOR_VERSION}:-coreos-stable-43"

FROM ghcr.io/ublue-os/akmods:${AKMODS_FLAVOR}-${FEDORA_MAJOR_VERSION}-${KERNEL} AS akmods

#if defined(NVIDIA)
FROM ghcr.io/ublue-os/akmods-nvidia-open:${AKMODS_FLAVOR}-${FEDORA_MAJOR_VERSION}-${KERNEL} AS akmods-nvidia-open
#endif

FROM scratch AS ctx
COPY /scripts /scripts
COPY /source /source
COPY /utils /utils

FROM ${BASE_IMAGE}:${FEDORA_MAJOR_VERSION} AS base

# --- 内部参数重声明 ---
ARG AKMODS_FLAVOR="main"
ARG BASE_IMAGE_NAME="${BASE_IMAGE_NAME}"
ARG FEDORA_MAJOR_VERSION=""
ARG IMAGE_NAME="calyx"
ARG IMAGE_VENDOR="jhuang"
ARG KERNEL=""
ARG SHA_HEAD_SHORT="dedbeef"
ARG IMAGE_TAG="latest"
ARG VERSION=""
ARG IMAGE_FLAVOR=""

# /* so these utils are available to all later RUNs */
ENV PATH="/tmp/bin/:${PATH}"

RUN --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/var \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=bind,from=akmods,src=/kernel-rpms,dst=/tmp/kernel-rpms \
    --mount=type=bind,from=akmods,src=/rpms/common,dst=/tmp/rpms/common \
    --mount=type=bind,from=akmods,src=/rpms/kmods,dst=/tmp/rpms/kmods \
    --mount=type=secret,id=GITHUB_TOKEN \
    /ctx/scripts/base/00_init.sh && \
    /ctx/scripts/base/01_install_packages.sh && \
    /ctx/scripts/base/02-install-common-kernel-akmods.sh && \
    /ctx/scripts/base/03-fetch.sh

#if defined(NVIDIA)
RUN --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/var \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=bind,from=akmods,src=/kernel-rpms,dst=/tmp/kernel-rpms \
    --mount=type=bind,from=akmods,src=/rpms/common,dst=/tmp/rpms/common \
    --mount=type=bind,from=akmods,src=/rpms/kmods,dst=/tmp/rpms/kmods \
    --mount=type=bind,from=akmods-nvidia-open,src=/rpms,dst=/tmp/rpms/nvidia \
    --mount=type=secret,id=GITHUB_TOKEN \
    /ctx/build_files/shared/build.sh && \
    /ctx/build_files/base/01-packages.sh && \
    /ctx/build_files/base/02-install-common-kernel-akmods.sh && \
    /ctx/build_files/base/03-fetch.sh && \
    /ctx/build_files/base/04-nvidia.sh
#endif