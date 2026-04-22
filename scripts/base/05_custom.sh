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

# Bash Prexec v0.6.0
ghcurl https://raw.githubusercontent.com/rcaloras/bash-preexec/b73ed5f7f953207b958f15b1773721dded697ac3/bash-preexec.sh --retry 3 -Lo /usr/share/bash-preexec

echo "::endgroup::"