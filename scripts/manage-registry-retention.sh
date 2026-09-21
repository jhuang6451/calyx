#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# 镜像生命周期与版本保留管理脚本
# - calyx-kmods 保留 <= 2 个版本
# - calyx (最终系统镜像) 保留 <= 3 个版本
# - 在 fedora-server 上执行 registry garbage-collect 物理释放磁盘空间
# ==============================================================================

REGISTRY="${REGISTRY:-registry.elix1r.top}"
KMODS_KEEP="${KMODS_KEEP:-2}"
CALYX_KEEP="${CALYX_KEEP:-3}"
SERVER_HOST="${SERVER_HOST:-fedora-server}"

# 自动判断协议 (本地端口/内网IP使用 http，域名使用 https)
if [[ "${REGISTRY}" =~ :[0-9]+$ ]] || [[ "${REGISTRY}" =~ ^127\. ]] || [[ "${REGISTRY}" =~ ^192\.168\. ]] || [[ "${REGISTRY}" =~ ^localhost ]]; then
  PROTO="http"
else
  PROTO="https"
fi

# 获取认证凭据
AUTH_TOKEN=$(jq -r --arg reg "${REGISTRY}" '.auths[$reg].auth // empty' "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/containers/auth.json" 2>/dev/null \
  || jq -r --arg reg "${REGISTRY}" '.auths[$reg].auth // empty' ~/.config/containers/auth.json 2>/dev/null \
  || echo "")

if [[ -n "${AUTH_TOKEN}" ]]; then
  AUTH_HEADER="Authorization: Basic ${AUTH_TOKEN}"
elif [[ "${PROTO}" == "https" ]]; then
  AUTH_HEADER="Authorization: Basic amh1YW5nOjYzM2MwNmUwYWE0ZWQ4NzE5YTFhYjRjMDVhMjVjZmRi"
else
  AUTH_HEADER=""
fi

echo "=========================================================="
echo "==> 执行镜像版本生命周期管理 (Registry: ${PROTO}://${REGISTRY})"
echo "    - calyx-kmods 保留版本数: ${KMODS_KEEP}"
echo "    - calyx       保留版本数: ${CALYX_KEEP}"
echo "=========================================================="

prune_repo() {
  local repo="$1"
  local keep_count="$2"
  local filter_regex="$3"

  echo "==> 检查仓库: ${repo} ..."
  local tags_json
  tags_json=$(curl -s -k ${AUTH_HEADER:+-H "${AUTH_HEADER}"} "${PROTO}://${REGISTRY}/v2/${repo}/tags/list" 2>/dev/null || echo "{}")
  
  local tags
  tags=$(echo "${tags_json}" | jq -r '.tags[]? // empty' | grep -E "${filter_regex}" | sort -V || true)
  
  if [[ -z "${tags}" ]]; then
    echo "    无匹配的版本标签。"
    return 0
  fi
  
  local tag_array=(${tags})
  local total=${#tag_array[@]}
  echo "    当前共有 ${total} 个版本标签: ${tag_array[*]}"
  
  if (( total <= keep_count )); then
    echo "    版本数 (${total}) <= 保留阈值 (${keep_count})，无需清理。"
    return 0
  fi
  
  local to_delete_count=$(( total - keep_count ))
  local delete_tags=("${tag_array[@]:0:to_delete_count}")
  echo "    即将清理超期的 ${to_delete_count} 个旧版本: ${delete_tags[*]}"
  
  for tag in "${delete_tags[@]}"; do
    echo "    -> 获取 ${repo}:${tag} 的 manifest digest..."
    local digest
    digest=$(curl -s -k -I ${AUTH_HEADER:+-H "${AUTH_HEADER}"} \
      -H "Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json" \
      "${PROTO}://${REGISTRY}/v2/${repo}/manifests/${tag}" | grep -i '^docker-content-digest:' | awk '{print $2}' | tr -d '\r\n')
      
    if [[ -n "${digest}" ]]; then
      echo "    -> 正在删除 ${repo}@${digest} (${tag}) ..."
      local resp
      resp=$(curl -s -k -w "%{http_code}" -o /dev/null -X DELETE ${AUTH_HEADER:+-H "${AUTH_HEADER}"} "${PROTO}://${REGISTRY}/v2/${repo}/manifests/${digest}")
      if [[ "${resp}" =~ ^20[0-4]$ ]]; then
        echo "    -> [成功] 已删除 ${tag} (${digest})"
      else
        echo "    -> [警告] 删除 ${tag} 失败，HTTP 响应码: ${resp}"
      fi
    else
      echo "    -> [警告] 无法获取 ${tag} 的 digest，跳过。"
    fi
  done
}

# 1. 清理 calyx-kmods (纯内核版本标签，如 7.2.5-200.fc44.x86_64)
prune_repo "calyx-kmods" "${KMODS_KEEP}" '^[0-9]+\.[0-9]+'

# 2. 清理 calyx (排除 latest / latest-nvidia / 44 / 44-nvidia 等浮动指针，只清理形如 44-7.2.5-nvidia 等带内核/日期的具体版本标签)
prune_repo "calyx" "${CALYX_KEEP}" '^[0-9]+-[0-9]+\.[0-9]+'

# 3. 触发垃圾回收释放物理存储 (优先本地 podman，其次 SSH)
echo "==> 正在触发 Registry 垃圾回收释放物理存储..."
if command -v podman >/dev/null 2>&1 && podman ps --format '{{.Names}}' 2>/dev/null | grep -q '^registry$'; then
  echo "    检测到当前为主机 (本地运行 registry 容器)，直接执行本地垃圾回收..."
  podman exec registry registry garbage-collect /etc/docker/registry/config.yml || true
elif ssh -o ConnectTimeout=5 "${SERVER_HOST}" "podman exec registry registry garbage-collect /etc/docker/registry/config.yml" 2>/dev/null; then
  echo "==> [成功] 远程磁盘孤儿数据块已完成垃圾回收与物理释放。"
else
  echo "==> [提示] 远程垃圾回收跳过或未连接上 ${SERVER_HOST}，将在远程定时任务中自动回收。"
fi

# 4. 本地 Podman 清理未使用的悬挂镜像
echo "==> 清理本地 Podman 悬挂镜像缓存..."
podman image prune -f || true

echo "==> 镜像生命周期管理执行完毕！"
