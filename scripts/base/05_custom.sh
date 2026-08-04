#!/usr/bin/bash
echo "::group:: ===$(basename "$0")==="
set -eoux pipefail

# Enable Flathub
flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Starship Shell Prompt
ghcurl "https://github.com/starship/starship/releases/latest/download/starship-$(uname -m)-unknown-linux-gnu.tar.gz" --retry 3 -o /tmp/starship.tar.gz
ghcurl "https://github.com/starship/starship/releases/latest/download/starship-$(uname -m)-unknown-linux-gnu.tar.gz.sha256" --retry 3 -o /tmp/starship.tar.gz.sha256

echo "$(cat /tmp/starship.tar.gz.sha256) /tmp/starship.tar.gz" | sha256sum --check
tar -xzf /tmp/starship.tar.gz -C /tmp
install -c -m 0755 /tmp/starship /usr/bin

# Nerdfont symbols
# to fix motd and prompt atleast temporarily
ghcurl "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip" --retry 3 -o /tmp/nerdfontsymbols.zip
unzip /tmp/nerdfontsymbols.zip -d /tmp
mkdir -p /usr/share/fonts/nerd-fonts/NerdFontsSymbolsOnly/
mv /tmp/SymbolsNerdFont*.ttf /usr/share/fonts/nerd-fonts/NerdFontsSymbolsOnly/
fc-cache -f /usr/share/fonts/nerd-fonts/NerdFontsSymbolsOnly/

# Bash Prexec v0.6.0
ghcurl https://raw.githubusercontent.com/rcaloras/bash-preexec/b73ed5f7f953207b958f15b1773721dded697ac3/bash-preexec.sh --retry 3 -Lo /usr/share/bash-preexec

# Install Clash Party (Mihomo Party) latest RPM
echo "Downloading and installing latest Clash Party RPM..."
CLASH_PARTY_RPM_URL=$(ghcurl "https://api.github.com/repos/mihomo-party-org/clash-party/releases/latest" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    assets = data.get("assets", [])
    rpm_assets = [a["browser_download_url"] for a in assets if a["name"].endswith(".rpm") and not a["name"].endswith(".sha256")]
    x86_assets = [u for u in rpm_assets if "x86_64" in u or "amd64" in u]
    print(x86_assets[0] if x86_assets else (rpm_assets[0] if rpm_assets else ""))
except Exception:
    sys.exit(1)
')

if [[ -n "${CLASH_PARTY_RPM_URL}" ]]; then
    echo "Fetching Clash Party from ${CLASH_PARTY_RPM_URL}"
    ghcurl "${CLASH_PARTY_RPM_URL}" -Lo /tmp/clash-party.rpm
    dnf5 -y install --setopt=install_weak_deps=False /tmp/clash-party.rpm
    rm -f /tmp/clash-party.rpm
else
    echo "ERROR: Failed to obtain Clash Party RPM download URL."
    exit 1
fi

echo "::endgroup::"