#!/usr/bin/bash
echo "::group:: ===$(basename "$0")==="
set -eoux pipefail

# Add Flathub to the image
mkdir -p /etc/flatpak/remotes.d/
curl --retry 3 -Lo /etc/flatpak/remotes.d/flathub.flatpakrepo https://dl.flathub.org/repo/flathub.flatpakrepo

systemctl enable flatpak-nuke-fedora.service      # source/configs/base
systemctl disable flatpak-add-fedora-repos.service

# This comes last because we can't afford to ship fedora flatpaks on the image
systemctl mask flatpak-add-fedora-repos.service
rm -f /usr/lib/systemd/system/flatpak-add-fedora-repos.service

echo "::endgroup::"