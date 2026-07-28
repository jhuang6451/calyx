# Calyx Custom Bootc Image

Calyx 是基于 Fedora Kinoite (KDE Ostree) 和 Universal Blue / Aurora 构建的自定义 `bootc` 操作系统镜像项目。

## 🌟 特性

- **Bootc 现代原生镜像架构**: 支持使用 `bootc switch` / `bootc upgrade` 进行操作系统镜像更新与无缝切换。
- **动态 NVIDIA 驱动支持**: 支持编译标准版 (`main`) 及 NVIDIA 独显驱动版 (`nvidia`)。
- **现代化软件与多媒体集成**: 预装 `dnf5`, `fastfetch`, `btop`, `restic`, `sunshine`, `tailscale` 等工具，替换 Negativo17 完整的 Mesa / VAAPI 硬件加速驱动。
- **自动化 CI/CD 工作流**: 支持 GitHub Actions 自动化矩阵构建、推送至 GHCR 以及 Cosign 镜像签名认证。

## 🛠️ 本地构建与调试

使用 `podman` 或 `Taskfile` 在本地构建镜像：

```bash
# 1. 设置脚本执行权限
chmod +x scripts/base/*.sh utils/*

# 2. 构建标准版镜像 (Fedora 44 / Linux 7.1)
podman build -t calyx:latest -f Containerfile .

# 3. 构建 NVIDIA 驱动版镜像
podman build --build-arg NVIDIA_ENABLED=true -t calyx:latest-nvidia -f Containerfile .
```

## 🚀 GitHub Actions CI/CD 工作流

项目已配置 GitHub Actions 工作流：[.github/workflows/build-and-push.yml](.github/workflows/build-and-push.yml)。

### 功能包含：
- **触发条件**:
  - 提交至 `main` / `master` 分支自动构建。
  - Pull Request 自动触发验证构建（不发布）。
  - 每周日 00:00 UTC 自动定时重构，同步 upstream 基础镜像与安全更新。
  - 支持在 GitHub Actions 页面进行 **Workflow Dispatch** 手动指定 Fedora 及 Kernel 版本构建。
- **镜像输出**: 镜像自动打包并推送到 GitHub Container Registry (`ghcr.io`)。
  - `ghcr.io/<owner>/calyx:latest`
  - `ghcr.io/<owner>/calyx:latest-nvidia`
  - `ghcr.io/<owner>/calyx:44-7.1.0`
- **Cosign 签名**: 使用 Keyless Cosign (GitHub OIDC) 为生成的 OCI 镜像自动签名。

### ⚙️ GitHub 仓库必要设置：
1. 访问 GitHub 仓库的 **Settings** -> **Actions** -> **General**。
2. 在 **Workflow permissions** 中选择 **Read and write permissions**。
3. 勾选 **Allow GitHub Actions to create and approve pull requests**。