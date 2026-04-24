#!/usr/bin/bash
set -eoux pipefail
# GitHub Actions 日志分组标记
echo "::group:: init"

# Speeds up local builds
dnf config-manager setopt keepcache=1

# Copy Base Configs to Image
# 注意：源路径末尾的 / 非常重要，它确保将 base 目录下的内容合并到根目录，
# 而不是在根目录下创建一个名为 base 的文件夹。
rsync -rvKl /ctx/source/configs/base/ /

# Install Utils to Tmp
# 注意：utils 目录在 ctx 镜像的根路径下，而不是在 source/utils 下。
mkdir -p /tmp/bin/
install -Dm0755 /ctx/utils/ghcurl /tmp/bin/ghcurl
install -Dm0755 /ctx/utils/copr-helpers.sh /tmp/bin/copr-helpers.sh

echo "::endgroup::"