#!/usr/bin/bash
set -eoux pipefail

echo "==================== [$(basename "$0")] START ===================="

# 提升 DNF 缓存效率
dnf5 config-manager setopt keepcache=1

# 准备临时目录与构建缓存目录 (针对 tmpfs /var 挂载预建必要子目录)
mkdir -p /tmp/bin /var/tmp /var/log/akmods /var/cache/akmods /var/lib/alternatives /var/lib/rpm /var/cache
chmod 1777 /tmp /var/tmp
chmod 777 /var/log/akmods /var/cache/akmods

# 安装构建辅助工具到 PATH
install -Dm0755 /ctx/utils/ghcurl /tmp/bin/ghcurl
install -Dm0755 /ctx/utils/copr-helpers.sh /tmp/bin/copr-helpers.sh

echo "==================== [$(basename "$0")] END ===================="