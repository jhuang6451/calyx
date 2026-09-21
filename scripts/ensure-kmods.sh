#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# 动态内核探测与驱动镜像按需构建脚本
# ==============================================================================

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_DIR}"

FEDORA_VERSION="${1:-44}"
BASE_IMAGE_NAME="${2:-kinoite}"
BASE_IMAGE_ORG="${3:-quay.io/fedora-ostree-desktops}"
REGISTRY="${4:-registry.elix1r.top}"

TARGET_BASE="${BASE_IMAGE_ORG}/${BASE_IMAGE_NAME}:${FEDORA_VERSION}"

echo "==> [1/4] 动态解析上游基础镜像内核: ${TARGET_BASE} ..."

# 确保基础镜像拉取到本地以提取元数据
if ! podman image exists "${TARGET_BASE}"; then
  echo "    拉取基础镜像 ${TARGET_BASE} ..."
  podman pull "${TARGET_BASE}"
fi

# 优先从镜像 Label 读取 ostree.linux，若未提供则通过容器内 rpm 查询
DETECTED_KERNEL=$(podman inspect "${TARGET_BASE}" --format '{{index .Config.Labels "ostree.linux"}}' 2>/dev/null || true)

if [[ -z "${DETECTED_KERNEL}" || "${DETECTED_KERNEL}" == "<no value>" ]]; then
  echo "    从容器内读取 kernel-core 版本..."
  DETECTED_KERNEL=$(podman run --rm "${TARGET_BASE}" rpm -q --queryformat "%{VERSION}-%{RELEASE}.%{ARCH}" kernel-core | head -n1 | tr -d '\r\n')
fi

if [[ -z "${DETECTED_KERNEL}" ]]; then
  echo "ERROR: 无法动态识别基础镜像中的内核版本！"
  exit 1
fi

echo "==> [2/4] 当前动态锁定的内核版本: ${DETECTED_KERNEL}"

# 保存当前锁定的内核版本到本地文件供 Taskfile 或其他工具读取
echo "${DETECTED_KERNEL}" > "${REPO_DIR}/.kernel-lock"

KMODS_IMAGE="${REGISTRY}/calyx-kmods:${DETECTED_KERNEL}"

check_image_exists() {
  local img="$1"
  if podman image exists "${img}"; then
    return 0
  fi
  if command -v skopeo >/dev/null 2>&1; then
    if skopeo inspect --tls-verify=false "docker://${img}" >/dev/null 2>&1; then
      return 0
    fi
  else
    local host_port="${img%%/*}"
    local path_tag="${img#*/}"
    local repo="${path_tag%:*}"
    local tag="${path_tag##*:}"
    for proto in http https; do
      if curl -s -k -f -o /dev/null -H "Accept: application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json" "${proto}://${host_port}/v2/${repo}/manifests/${tag}" 2>/dev/null; then
        return 0
      fi
    done
  fi
  return 1
}

echo "==> [3/4] 检查私有镜像仓或本地是否存在驱动镜像: ${KMODS_IMAGE} ..."
if check_image_exists "${KMODS_IMAGE}"; then
  echo "==> [OK] 驱动镜像已存在，跳过编译。"
else
  echo "==> [BUILD] 未找到匹配的驱动镜像，开始本地构建驱动镜像..."
  podman build \
    --build-arg FEDORA_MAJOR_VERSION="${FEDORA_VERSION}" \
    --build-arg KERNEL_VER="${DETECTED_KERNEL}" \
    -t "${KMODS_IMAGE}" \
    -f Containerfile.kmods .

  echo "==> 正在推送驱动镜像至私有仓库: ${KMODS_IMAGE} ..."
  podman push --tls-verify=false "${KMODS_IMAGE}"
  echo "==> 驱动镜像推送成功！"

  # 执行镜像版本生命周期管理 (保留 <= 2 个版本并触发 GC)
  echo "==> 执行驱动镜像版本淘汰策略..."
  REGISTRY="${REGISTRY}" "${REPO_DIR}/scripts/manage-registry-retention.sh" || true
fi

echo "==> [4/4] 内核驱动版本准备就绪: ${DETECTED_KERNEL}"
