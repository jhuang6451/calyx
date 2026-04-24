#!/usr/bin/bash
echo "::group:: ===$(basename "$0")==="
set -eoux pipefail

# Remove Existing Kernel
for pkg in kernel kernel{-core,-modules,-modules-core,-modules-extra,-tools-libs,-tools}; do
    rpm --erase "${pkg}" --nodeps
done

# cleanup leftovers that are not covered by kernel-* packages for some reason
rm -rf /usr/lib/modules

# Install Kernel
export KERNEL_INSTALL_SKIP_PREGEN_INITRD=yes
dnf5 -y install \
    /tmp/kernel-rpms/kernel-[0-9]*.rpm \
    /tmp/kernel-rpms/kernel-core-*.rpm \
    /tmp/kernel-rpms/kernel-modules-*.rpm

dnf5 -y install --setopt=install_weak_deps=False \
    /tmp/kernel-rpms/kernel-devel-*.rpm

dnf5 versionlock add kernel kernel-devel kernel-devel-matched kernel-core kernel-modules kernel-modules-core kernel-modules-extra

dnf5 -y install --setopt=install_weak_deps=False \
    /tmp/rpms/{common,kmods}/*xone*.rpm /tmp/rpms/{common,kmods}/*openrazer*.rpm || true

dnf5 -y install --setopt=install_weak_deps=False \
    /tmp/rpms/{kmods,common}/*v4l2loopback*.rpm || true

mkdir -p /etc/pki/akmods/certs
ghcurl "https://github.com/ublue-os/akmods/raw/refs/heads/main/certs/public_key.der" --retry 3 -Lo /etc/pki/akmods/certs/akmods-ublue.der


echo "::endgroup::"