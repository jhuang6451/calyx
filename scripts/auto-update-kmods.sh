#!/usr/bin/env bash
set -euo pipefail

# 兼容旧服务调用的入口，统一转发至 ensure-kmods.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/ensure-kmods.sh" "$@"
