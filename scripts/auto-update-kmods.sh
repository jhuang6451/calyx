#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_DIR}"

FEDORA_VERSION="${1:-44}"
BASE_CONTAINER="registry.fedoraproject.org/fedora:${FEDORA_VERSION}"

echo "==> 检查 Fedora ${FEDORA_VERSION} 最新内核版本..."
LATEST_KERNEL=$(podman run --rm "${BASE_CONTAINER}" dnf5 repoquery kernel-core --latest-limit 1 --queryformat "%{VERSION}-%{RELEASE}.%{ARCH}" 2>/dev/null | tail -n1 | tr -d '\r')

if [[ -z "${LATEST_KERNEL}" ]]; then
  echo "ERROR: 无法获取最新内核版本号"
  exit 1
fi

echo "==> 上游最新内核: ${LATEST_KERNEL}"

TARGET_MODULE_DIR="source/configs/base/usr/lib/modules/${LATEST_KERNEL}"

if [[ -d "${TARGET_MODULE_DIR}/extra/nvidia" && -d "${TARGET_MODULE_DIR}/extra/ntfs" && -d "${TARGET_MODULE_DIR}/extra/v4l2loopback" ]]; then
  echo "==> 驱动已是最新版本 (${LATEST_KERNEL})，无需重复编译。"
  exit 0
fi

echo "==> 发现新内核或驱动缺失，开始在隔离容器中编译驱动并输出产物..."

# 运行本地容器编译全套驱动
podman run --rm -v "${REPO_DIR}:/workspace:z" "${BASE_CONTAINER}" bash -c "
  set -eoux pipefail
  dnf5 -y install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm || true
  dnf5 config-manager setopt fedora-repos-archive.enabled=1 || true
  
  dnf5 -y install git make gcc kernel-core kernel-devel akmod-v4l2loopback akmod-nvidia autoconf automake libtool libgcrypt-devel libuuid-devel gnutls-devel
  
  KERNEL_VER=\"\$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core | head -n1)\"
  echo \"Target Kernel: \${KERNEL_VER}\"
  
  # 1. 编译 akmods 模块 (v4l2loopback & nvidia)
  mkdir -p /var/log/akmods /var/cache/akmods /tmp /var/tmp
  chmod 1777 /tmp /var/tmp
  chmod 777 /var/log/akmods /var/cache/akmods
  akmods --verbose --force --kernels \"\${KERNEL_VER}\"
  
  # 清理旧内核驱动，保持仓库轻量
  rm -rf /workspace/source/configs/base/usr/lib/modules/*
  
  mkdir -p \"/workspace/source/configs/base/usr/lib/modules/\${KERNEL_VER}/extra/v4l2loopback\"
  mkdir -p \"/workspace/source/configs/base/usr/lib/modules/\${KERNEL_VER}/extra/nvidia\"
  find \"/usr/lib/modules/\${KERNEL_VER}\" -name \"*v4l2loopback*.ko*\" -exec cp -a {} \"/workspace/source/configs/base/usr/lib/modules/\${KERNEL_VER}/extra/v4l2loopback/\" \;
  find \"/usr/lib/modules/\${KERNEL_VER}\" -name \"*nvidia*.ko*\" -exec cp -a {} \"/workspace/source/configs/base/usr/lib/modules/\${KERNEL_VER}/extra/nvidia/\" \;
  
  # 2. 编译 linux-ntfs 驱动
  git clone --depth 1 https://github.com/namjaejeon/linux-ntfs.git /tmp/linux-ntfs
  cd /tmp/linux-ntfs
  make KDIR=\"/usr/src/kernels/\${KERNEL_VER}\"
  mkdir -p \"/workspace/source/configs/base/usr/lib/modules/\${KERNEL_VER}/extra/ntfs\"
  install -m 0644 /tmp/linux-ntfs/ntfs.ko \"/workspace/source/configs/base/usr/lib/modules/\${KERNEL_VER}/extra/ntfs/ntfs.ko\"
  
  # 3. 编译 ntfsprogs-plus 用户态工具与运行库
  git clone --depth 1 https://github.com/ntfsprogs-plus/ntfsprogs-plus.git /tmp/ntfsprogs-plus
  cd /tmp/ntfsprogs-plus
  ./autogen.sh
  ./configure --prefix=/usr --exec-prefix=/usr --sbindir=/usr/sbin --bindir=/usr/bin --libdir=/usr/lib64
  make -j\$(nproc)
  make install DESTDIR=/tmp/ntfs-dist
  
  mkdir -p /workspace/source/configs/base/usr/bin /workspace/source/configs/base/usr/sbin /workspace/source/configs/base/usr/lib64
  cp -a /tmp/ntfs-dist/usr/bin/* /workspace/source/configs/base/usr/bin/ 2>/dev/null || true
  cp -a /tmp/ntfs-dist/usr/sbin/* /workspace/source/configs/base/usr/sbin/ 2>/dev/null || true
  cp -a /tmp/ntfs-dist/usr/lib64/libntfs.so* /workspace/source/configs/base/usr/lib64/ 2>/dev/null || true
"

echo "==> 驱动编译完成，检查 Git 变动并推送..."
git add -A source/configs/base/usr/
if git diff --staged --quiet; then
  echo "==> 没有产生文件变更。"
else
  git commit -m "chore(kmods): update kernel modules and tools for ${LATEST_KERNEL}"
  echo "==> 正在推送到远程仓库以触发 GitHub Actions 构建..."
  git push origin HEAD
  echo "==> 推送成功！云端 GitHub Actions 构建已自动拉起。"
fi
