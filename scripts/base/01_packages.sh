#!/usr/bin/bash
echo "==================== [$(basename "$0")] START ===================="
set -ouex pipefail

# NOTE:
# Packages are split into FEDORA_PACKAGES and COPR_PACKAGES to prevent
# malicious COPRs from injecting fake versions of Fedora packages.
# Fedora packages are installed first in bulk (safe).
# COPR packages are installed individually with isolated enablement.

# ==========================================================
#  软件源与 RPM Fusion 完整版多媒体/硬件加速驱动配置
# ==========================================================
# 启用 RPM Fusion Free 和 Nonfree 仓库
if ! rpm -q rpmfusion-free-release &>/dev/null; then
    dnf5 -y install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm || true
fi
if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
    dnf5 -y install https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm || true
fi

# 安装完整版多媒体编解码器及 Mesa 硬件加速补充驱动 (freeworld)
MULTIMEDIA_PACKAGES=(
    ffmpeg
    ffmpeg-libs
    intel-vaapi-driver
    libfdk-aac
    libva-utils
    mesa-va-drivers-freeworld
    mesa-vulkan-drivers-freeworld
    pipewire-libs-extra
)

echo "Installing ${#MULTIMEDIA_PACKAGES[@]} multimedia packages from RPM Fusion..."
dnf5 -y install --setopt=install_weak_deps=False "${MULTIMEDIA_PACKAGES[@]}" || true

# ==========================================================
#  官方源软件包安装 (整合用户 rpm_list.txt)
# ==========================================================
FEDORA_PACKAGES=(
    # --- [网络身份认证与文件共享 / Network Authentication & File Sharing] ---
    openssh-server           # OpenSSH 服务端
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
    NetworkManager-tui       # NM 命令行及终端 UI 界面 (nmtui)

    # --- [数据备份与安全 / Data Backup & Security] ---
    restic                   # 现代化的加密备份工具
    rclone

    # --- [容器与虚拟化 / Container & Virtualization] ---
    podman
    distrobox
    flatpak-spawn            # 允许在 Flatpak 沙盒内调用宿主机命令
    qemu-kvm                 # 虚拟化组件 (@virtualization)
    libvirt
    virt-manager

    # --- [终端与开发工具 / Terminal & Dev Tools] ---
    git
    gh                       # GitHub CLI
    zsh                      # 强大的 Shell 环境
    tmux                     # 终端复用器
    fastfetch                # 系统信息展示
    gum                      # 增强脚本交互的 UI 工具
    btop                     # 资源监视器
    cmatrix                  # 终端黑客帝国特效
    stow                     # Dotfiles 管理工具
    helix                    # 现代文本编辑器 (hx)
    cmake                    # 编译构建工具
    autoconf
    automake
    libtool
    gcc
    gcc-c++
    golang                   # Go 语言环境
    nodejs                   # Node.js 环境
    python3-pip              # Python 包管理器

    # --- [硬件管理与底层调试 / Hardware & Low-level Tools] ---
    alsa-firmware            # 声卡固件
    evtest                   # 输入设备调试
    igt-gpu-tools            # GPU 性能分析
    input-remapper           # 强大的按键映射工具
    lm_sensors               # 温度传感器监控
    lshw                     # 硬件信息列举
    nvtop                    # GPU 资源占用实时监控
    openrgb-udev-rules       # 灯效同步支持
    powertop                 # 笔记本省电优化工具
    powerstat
    squashfs-tools           # 文件系统压缩工具
    grub2-tools-extra        # 引导管理增强
    hwloc-libs               # 硬件拓扑分析库
    numactl-libs             # NUMA 内存管理库
    stress-ng                # 压力测试工具
    pciutils-devel           # PCI 设备开发库
    android-tools            # Android ADB 与 Fastboot 工具

    # --- [图形与游戏工具 / Graphics & Gaming] ---
    gamescope                # Valve 窗口合成器
    steam                    # Steam 游戏平台
    gparted                  # 磁盘分区管理工具

    # --- [系统实用程序 / System Utilities] ---
    unzip                    # 压缩包解压工具
    zram-generator           # systemd zram 动态生成工具
    xcb-util-cursor          # Qt6 XCB platform cursor dependency
    ksystemlog               # KDE 日志查看器
    setools-console          # SELinux 调试工具
    tcpdump                  # 抓包工具
    traceroute               # 路由追踪
    symlinks                 # 软链接管理
    git-credential-libsecret # Git 凭据管理器
    kate                     # KDE 文本编辑器
    kcm-fcitx5               # KDE 输入法设置界面
    ksshaskpass              # SSH 密码询问器
    libxcrypt-compat         # 兼容旧版本加密算法
    fcitx5
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

echo "Installing ${#FEDORA_PACKAGES[@]} packages from Fedora repos..."
dnf5 -y install --setopt=install_weak_deps=False "${FEDORA_PACKAGES[@]}"

# ==========================================================
#  三方源软件包安装 (Google Chrome, Tailscale, VSCode)
# ==========================================================
# Tailscale
echo "Installing tailscale from official repo..."
rpm --import https://pkgs.tailscale.com/stable/fedora/repo.gpg
dnf5 config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf5 config-manager setopt tailscale-stable.enabled=0
dnf5 -y install --setopt=install_weak_deps=False --enablerepo='tailscale-stable' tailscale

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
dnf5 -y install --setopt=install_weak_deps=False --enablerepo=code code

# Google Chrome
echo "Installing Google Chrome from Google repo..."
if [[ -L /opt ]]; then
    rm -f /opt
    mkdir -p /opt
fi
rpm --import https://dl.google.com/linux/linux_signing_key.pub
cat <<EOF > /etc/yum.repos.d/google-chrome.repo
[google-chrome]
name=google-chrome
baseurl=http://dl.google.com/linux/chrome/rpm/stable/\$basearch
enabled=0
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
dnf5 -y install --setopt=install_weak_deps=False --enablerepo=google-chrome google-chrome-stable

# ==========================================================
#  Copr 源软件包安装
# ==========================================================
echo "Installing COPR packages with isolated repo enablement..."
source /tmp/bin/copr-helpers.sh

# Sunshine from lizardbyte/beta COPR
copr_install_isolated "lizardbyte/beta" \
    "sunshine"

# ==========================================================
#  软件包排除 (整合 rpm_list.txt 中的精简项)
# ==========================================================
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
    khelpcenter                # 移除 KDE 帮助中心
    plasma-discover            # 移除 Discover 软件中心
    plasma-discover-rpm-ostree # 禁用 Discover 修改系统 RPM 包的权限
    plasma-welcome-fedora
    podman-docker              # 移除 Docker 别名以避免脚本冲突
    # --- 来自 rpm_list.txt 的精简包 ---
    plasma-nm-pptp             # 移除无用的 VPN 协议插件
    plasma-nm-sstp
    plasma-nm-openconnect
    plasma-nm-vpnc
    plasma-nm-l2tp
    abrt                       # 移除 ABRT 崩溃报告服务系列
    abrt-addon-ccpp
    abrt-addon-kerneloops
    abrt-addon-pstoreoops
    abrt-addon-vmcore
    abrt-addon-xorg
    abrt-cli
    abrt-dbus
    abrt-desktop
    abrt-gui
    abrt-gui-libs
    abrt-libs
    abrt-plugin-bodhi
    abrt-tui
    kdebugsettings             # 移除调试设置工具
    plasma-desktop-doc         # 移除桌面文档
    kpat                       # 移除 KDE 预装小游戏
    kmines
    kmahjongg
    kde-partitionmanager       # 移除分区工具 (已选用 GParted)
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

# Remove excluded packages if they are installed (use rpm --noscripts to bypass container scriptlet failures)
if [[ "${#EXCLUDED_PACKAGES[@]}" -gt 0 ]]; then
    readarray -t INSTALLED_EXCLUDED < <(rpm -qa --queryformat='%{NAME}\n' "${EXCLUDED_PACKAGES[@]}" 2>/dev/null || true)
    if [[ "${#INSTALLED_EXCLUDED[@]}" -gt 0 ]]; then
        echo "Removing ${#INSTALLED_EXCLUDED[@]} excluded packages via rpm --nodeps --noscripts..."
        rpm -e --nodeps --noscripts "${INSTALLED_EXCLUDED[@]}" || true
    else
        echo "No excluded packages found to remove."
    fi
fi


echo "==================== [$(basename "$0")] END ===================="