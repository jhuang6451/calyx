#!/usr/bin/bash
set -eoux pipefail
# GitHub Actions 日志分组标记
echo "::group:: init"

# Speeds up local builds
dnf5 config-manager setopt keepcache=1

# Copy Base Configs to Image
# 注意：源路径末尾的 / 非常重要，它确保将 base 目录下的内容合并到根目录，
# 而不是在根目录下创建一个名为 base 的文件夹。
rsync -rvKl /ctx/source/configs/base/ /

# Install Utils to Tmp
mkdir -p /tmp/bin/ /var/tmp /var/log/akmods /var/cache/akmods
chmod 1777 /tmp /var/tmp
chmod 777 /var/log/akmods /var/cache/akmods
install -Dm0755 /ctx/utils/ghcurl /tmp/bin/ghcurl
install -Dm0755 /ctx/utils/copr-helpers.sh /tmp/bin/copr-helpers.sh

echo "::endgroup::"