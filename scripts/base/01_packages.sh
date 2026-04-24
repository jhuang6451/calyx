#!/usr/bin/bash
echo "::group:: ===$(basename "$0")==="
set -ouex pipefail

# NOTE:
# Packages are split into FEDORA_PACKAGES and COPR_PACKAGES to prevent
# malicious COPRs from injecting fake versions of Fedora packages.
# Fedora packages are installed first in bulk (safe).
# COPR packages are installed individually with isolated enablement.

# ==========================================================
#  软件源与优先级配置
# ==========================================================
# 使用 negativo17 仓库并设置高优先级（priority=90,数字越小优先级越高），
# 优先安装此仓库提供的完整版驱动和多媒体插件，覆盖官方仓库的阉割版。
if ! grep -q fedora-multimedia <(dnf5 repolist); then
    # Enable or Install Repofile
    dnf5 config-manager setopt fedora-multimedia.enabled=1 ||
        dnf5 config-manager addrepo --from-repofile="https://negativo17.org/repos/fedora-multimedia.repo"
fi

dnf5 config-manager setopt fedora-multimedia.priority=90

# ==========================================================
#  硬件加速与图形驱动替换
# ==========================================================
# may break SDDM/KWin when upgraded
dnf5 versionlock add "qt6-*"

OVERRIDES=(
    "intel-gmmlib"
    "intel-mediasdk"
    "intel-vpl-gpu-rt"
    "libheif"
    "libva"
    "libva-intel-media-driver"
    "mesa-dri-drivers"
    "mesa-filesystem"
    "mesa-libEGL"
    "mesa-libGL"
    "mesa-libgbm"
    "mesa-va-drivers"
    "mesa-vulkan-drivers"
)

dnf5 distro-sync --skip-unavailable -y --repo='fedora-multimedia' "${OVERRIDES[@]}"
dnf5 versionlock add "${OVERRIDES[@]}"

# 多媒体与闭源驱动补丁包
NEGATIVO_PACKAGES=(
    ffmpeg
    ffmpeg-libs
    intel-vaapi-driver
    libfdk-aac
    libva-utils
    pipewire-libs-extra
    uld
)

echo "Installing ${#NEGATIVO_PACKAGES[@]} from Negativo..."
dnf5 -y install "${NEGATIVO_PACKAGES[@]}"

# ==========================================================
#  官方源软件包安装
# ==========================================================
FEDORA_PACKAGES=(
    # --- [网络身份认证与文件共享 / Network Authentication & File Sharing] ---
    adcli                    # 用于 Active Directory 域加入
    krb5-workstation         # Kerberos 客户端，企业内网认证必备
    samba-winbind            # 与 Windows 域整合的核心组件
    samba-winbind-clients
    samba-winbind-modules
    davfs2                   # 挂载 WebDAV 网盘
    gvfs                     # 虚拟文件系统，让文件管理器能访问网络路径
    gvfs-fuse
    apr                      # Apache 运行库，底层系统依赖
    apr-util
    autofs                   # 自动挂载远程共享

    # --- [数据备份与安全 / Data Backup & Security] ---
    restic                   # 现代化的加密备份工具
    rclone

    # --- [容器与虚拟化 / Container & Virtualization] ---
    podman
    distrobox
    flatpak-spawn            # 允许在 Flatpak 沙盒内调用宿主机命令

    # --- [终端工具 / Terminal Tools] ---
    zsh                      # 强大的 Shell 环境
    tmux                     # 终端复用器
    fastfetch                # 系统信息展示
    gum                      # 增强脚本交互的 UI 工具
    btop                     # 资源监视器，htop 的现代替代品

    # --- [硬件管理与底层工具 / Hardware Tools] ---
    alsa-firmware            # 声卡固件
    evtest                   # 输入设备调试
    igt-gpu-tools            # GPU 性能分析
    input-remapper           # 强大的按键映射工具
    # iwd                      # 现代 Wi-Fi 守护进程 #TODO
    # libratbag-ratbagd        # 游戏鼠标配置 (Piper 驱动)
    lm_sensors               # 温度传感器监控
    lshw                     # 硬件信息列举
    nvtop                    # GPU 资源占用实时监控
    openrgb-udev-rules       # 灯效同步支持
    powertop                 # 笔记本省电优化工具
    powerstat
    squashfs-tools           # 文件系统压缩工具
    grub2-tools-extra        # 引导管理增强

    # --- [系统实用程序 / System Utilities] ---
    ksystemlog               # KDE 日志查看器
    setools-console          # SELinux 调试工具
    tcpdump                  # 抓包工具
    traceroute               # 路由追踪
    symlinks                 # 软链接管理
    gcc                      # 基础编译器，部分底层操作需要
    git-credential-libsecret # Git 凭据管理器
    kate                     # KDE 文本编辑器
    kcm-fcitx5               # KDE 输入法设置界面
    ksshaskpass              # SSH 密码询问器
    libxcrypt-compat         # 兼容旧版本加密算法
    fcitx5-chinese-addons
    fcitx5-configtool
    fcitx5-gtk
    fcitx5-qt
)

# Version-specific Fedora package additions
case "$FEDORA_MAJOR_VERSION" in
    43)
        FEDORA_PACKAGES+=(
        )
        ;;
    44)
        FEDORA_PACKAGES+=(
        )
        ;;
esac

# Prevent partial upgrading
# https://github.com/ublue-os/aurora/issues/1227
dnf5 versionlock add plasma-desktop

echo "Installing ${#FEDORA_PACKAGES[@]} packages from Fedora repos..."
dnf5 -y install "${FEDORA_PACKAGES[@]}"

# ==========================================================
#  三方源软件包安装
# ==========================================================
# Tailscale
echo "Installing tailscale from official repo..."
dnf5 config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf5 config-manager setopt tailscale-stable.enabled=0
dnf5 -y install --enablerepo='tailscale-stable' tailscale

# VSCode
echo "Installing Visual Studio Code from Microsoft repo..."
rpm --import https://packages.microsoft.com/keys/microsoft.asc

cat <<EOF > /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=0
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

dnf5 -y install --enablerepo=code code

# ==========================================================
#  Copr 源软件包安装
# ==========================================================
echo "Installing COPR packages with isolated repo enablement..."
source /tmp/bin/copr-helpers.sh

# Sunshine from lizardbyte/beta COPR
copr_install_isolated "lizardbyte/beta" \
    "sunshine"

# ==========================================================
#  软件包排除
# ==========================================================
# Packages to exclude
EXCLUDED_PACKAGES=(
    akonadi-server             # 移除臃肿的 KDE PIM 服务以节省 CPU 和内存
    akonadi-server-mysql
    fedora-bookmarks
    fedora-third-party
    ffmpegthumbnailer
    firefox
    firefox-langpacks
    firewall-config            # 优先使用系统设置自带的防火墙配置
    kcharselect
    khelpcenter
    plasma-discover-rpm-ostree # 禁用 Discover 修改系统 RPM 包的权限
    plasma-welcome-fedora
    podman-docker              # 移除 Docker 别名以避免脚本冲突
)

# Version-specific package exclusions
case "$FEDORA_MAJOR_VERSION" in
    43)
        EXCLUDED_PACKAGES+=()
        ;;
    44)
        EXCLUDED_PACKAGES+=()
        ;;
esac

# Remove excluded packages if they are installed
if [[ "${#EXCLUDED_PACKAGES[@]}" -gt 0 ]]; then
    readarray -t INSTALLED_EXCLUDED < <(rpm -qa --queryformat='%{NAME}\n' "${EXCLUDED_PACKAGES[@]}" 2>/dev/null || true)
    if [[ "${#INSTALLED_EXCLUDED[@]}" -gt 0 ]]; then
        dnf5 -y remove "${INSTALLED_EXCLUDED[@]}"
    else
        echo "No excluded packages found to remove."
    fi
fi


echo "::endgroup::"