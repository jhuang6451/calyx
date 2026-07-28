#!/usr/bin/bash
echo "::group:: ===$(basename "$0")==="
set -eoux pipefail

# Disable all COPR repos (should already be disabled by helpers, but ensure)
for i in /etc/yum.repos.d/_copr:*.repo; do
    if [[ -f "$i" ]]; then
        sed -i 's@enabled=1@enabled=0@g' "$i"
    fi
done

# Disable RPM Fusion repos
for i in /etc/yum.repos.d/rpmfusion-*.repo; do
    if [[ -f "$i" ]]; then
        sed -i 's@enabled=1@enabled=0@g' "$i"
    fi
done

# Disable fedora-coreos-pool if it exists
if [ -f /etc/yum.repos.d/fedora-coreos-pool.repo ]; then
    sed -i 's@enabled=1@enabled=0@g' /etc/yum.repos.d/fedora-coreos-pool.repo
fi

# Revert back to upstream defaults
dnf5 config-manager setopt keepcache=0
dnf5 versionlock clear

rm -rf /.gitkeep

# Ensure plugdev group has sysusers.d entry for bootc lint
mkdir -p /usr/lib/sysusers.d
echo "g plugdev - -" > /usr/lib/sysusers.d/plugdev.conf

find /var/* -maxdepth 0 -type d \! -name cache -exec rm -fr {} \;

# Clean /run directory for bootc lint (nonempty-run-tmp)
find /run -mindepth 1 \
  ! -path '/run/systemd' \
  ! -path '/run/systemd/resolve' \
  ! -path '/run/systemd/resolve/stub-resolv.conf' \
  ! -path '/run/secrets' \
  ! -path '/run/secrets/*' \
  ! -path '/run/.containerenv' \
  -delete 2>/dev/null || true

rm -rf /tmp/*
mkdir -p /var/tmp

rm -rf /opt && ln -s /var/opt /opt # /opt 是指向向 /var/opt 的软链接，保持兼容性

echo "::endgroup::"