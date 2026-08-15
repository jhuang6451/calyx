#!/usr/bin/bash
set -eoux pipefail

echo "::group:: ===$(basename "$0")==="

# 1. 救援模式与紧急启动支持 (CoreOS sulogin generator)
mkdir -p /usr/lib/systemd/system-generators
ghcurl "https://raw.githubusercontent.com/coreos/fedora-coreos-config/refs/heads/stable/overlay.d/05core/usr/lib/systemd/system-generators/coreos-sulogin-force-generator" --retry 3 -Lo /usr/lib/systemd/system-generators/coreos-sulogin-force-generator
chmod +x /usr/lib/systemd/system-generators/coreos-sulogin-force-generator

# 2. 默认 Shell 设置为 /bin/zsh (避免在 bootc 构建中调用 chsh 修改 /etc/passwd)
rm -f /usr/bin/chsh /usr/bin/lchsh
mkdir -p /etc/default
if [ -f /etc/default/useradd ]; then
    sed -i 's|^SHELL=.*|SHELL=/bin/zsh|' /etc/default/useradd || echo "SHELL=/bin/zsh" >> /etc/default/useradd
else
    echo "SHELL=/bin/zsh" > /etc/default/useradd
fi
sed -i 's|^root:\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):.*|root:\1:\2:\3:\4:\5:/bin/zsh|' /etc/passwd

# 3. 字体与桌面体验修复
# 修复部分 Flatpak 应用中文字体显示
ln -s "/usr/share/fonts/google-noto-sans-cjk-fonts" "/usr/share/fonts/noto-cjk" 2>/dev/null || true

# 屏蔽 KDE Discover 容易引起混淆的系统级更新弹窗
rm -f /etc/xdg/autostart/org.kde.discover.notifier.desktop

# 4. Samba 用户共享开箱即用支持
mkdir -p /var/lib/samba/usershares
chown -R root:usershares /var/lib/samba/usershares 2>/dev/null || true
firewall-offline-cmd --add-service=samba --add-service=samba-client || true
setsebool -P samba_enable_home_dirs=1 || true
setsebool -P samba_export_all_ro=1 || true
setsebool -P samba_export_all_rw=1 || true
if [ -f /etc/samba/smb.conf ]; then
    sed -i '/^\[homes\]/,/^\[/{/^\[homes\]/d;/^\[/!d}' /etc/samba/smb.conf
fi

# 5. Starship Shell 提示符
ghcurl "https://github.com/starship/starship/releases/latest/download/starship-$(uname -m)-unknown-linux-gnu.tar.gz" --retry 3 -o /tmp/starship.tar.gz
ghcurl "https://github.com/starship/starship/releases/latest/download/starship-$(uname -m)-unknown-linux-gnu.tar.gz.sha256" --retry 3 -o /tmp/starship.tar.gz.sha256
echo "$(cat /tmp/starship.tar.gz.sha256) /tmp/starship.tar.gz" | sha256sum --check
tar -xzf /tmp/starship.tar.gz -C /tmp
install -c -m 0755 /tmp/starship /usr/bin

# 6. Nerd Fonts Symbols 字体图标
ghcurl "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip" --retry 3 -o /tmp/nerdfontsymbols.zip
unzip /tmp/nerdfontsymbols.zip -d /tmp/nerdfonts
mkdir -p /usr/share/fonts/nerd-fonts/NerdFontsSymbolsOnly/
mv /tmp/nerdfonts/SymbolsNerdFont*.ttf /usr/share/fonts/nerd-fonts/NerdFontsSymbolsOnly/
fc-cache -f /usr/share/fonts/nerd-fonts/NerdFontsSymbolsOnly/

# 7. Bash Preexec
ghcurl https://raw.githubusercontent.com/rcaloras/bash-preexec/b73ed5f7f953207b958f15b1773721dded697ac3/bash-preexec.sh --retry 3 -Lo /usr/share/bash-preexec

# 8. 安装 Clash Party (Mihomo Party) 最新 RPM
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
