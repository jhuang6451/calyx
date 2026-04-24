#!/usr/bin/bash
echo "::group:: ===$(basename "$0")==="
set -eoux pipefail

# use CoreOS' generator for emergency/rescue boot
# see detail: https://github.com/ublue-os/main/issues/653
mkdir -p /usr/lib/systemd/system-generators
ghcurl "https://raw.githubusercontent.com/coreos/fedora-coreos-config/refs/heads/stable/overlay.d/05core/usr/lib/systemd/system-generators/coreos-sulogin-force-generator" --retry 3 -Lo /usr/lib/systemd/system-generators/coreos-sulogin-force-generator
chmod +x /usr/lib/systemd/system-generators/coreos-sulogin-force-generator

# Footgun, See: https://github.com/ublue-os/main/issues/598
# chsh 会修改 /etc/passwd，在 bootc 构建阶段操作该文件会导致严重的升级冲突。
# 若想更改默认 Shell，应通过修改 /etc/default/useradd 中的 SHELL 变量来实现。
rm -f /usr/bin/chsh /usr/bin/lchsh

# secure_path 是 sudo 命令运行时的信任路径。此处追加路径，方便用户在 sudo 下直接调用其工具。
# 采用 sed 修改主配置是为了利用 bootc 的三方合并机制，使这里添加的路径能与官方未来的更新融合。
# 若用户日后在 sudoers.d 中定义了新的配置，系统将以用户的“最终解释权”为准。
# 示例 (Homebrew):
# sed -Ei "s/secure_path = (.*)/secure_path = \1:\/home\/linuxbrew\/.linuxbrew\/bin/" /etc/sudoers

# https://github.com/ublue-os/main/pull/334
# 修复某些 flatpak 应用无法正常显示中文字体的问题。
ln -s "/usr/share/fonts/google-noto-sans-cjk-fonts" "/usr/share/fonts/noto-cjk"

# KDE Discover: 屏蔽让用户感到困惑的“系统更新”提示（在 bootc 系统上，升级应通过 ujust update 等专用工具完成）。
rm /etc/xdg/autostart/org.kde.discover.notifier.desktop

# Make Samba usershares work OOTB
mkdir -p /var/lib/samba/usershares
chown -R root:usershares /var/lib/samba/usershares
firewall-offline-cmd --service=samba --service=samba-client
setsebool -P samba_enable_home_dirs=1
setsebool -P samba_export_all_ro=1
setsebool -P samba_export_all_rw=1
sed -i '/^\[homes\]/,/^\[/{/^\[homes\]/d;/^\[/!d}' /etc/samba/smb.conf

echo "::endgroup::"