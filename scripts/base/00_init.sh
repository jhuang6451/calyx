#!/usr/bin/bash
set -eoux pipefail
# GitHub Actions 日志分组标记
echo "::group:: init"

# Speeds up local builds
dnf config-manager setopt keepcache=1

# Copy Base Configs to Image
rsync -rvKl /ctx/source/configs/base /

# Install Utils to Tmp
mkdir -p /tmp/bin/
install -Dm0755 /ctx/utils/ghcurl /tmp/bin/ghcurl
install -Dm0755 /ctx/utils/copr-helpers.sh /tmp/bin/copr-helpers.sh

echo "::endgroup::"