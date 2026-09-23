---
name: calyx-maintenance
description: >-
  Comprehensive guide and standard operating procedures (SOP) for developing, maintaining,
  building, and troubleshooting Calyx (an immutable Fedora Kinoite bootc OS image with NVIDIA drivers).
  Activate this skill whenever modifying Calyx package manifests, drivers, configurations, Taskfile,
  Containerfile, automated build pipelines on fedora-server, or managing private registry storage.
---

# Calyx 系统开发与运维维护手册 (Calyx Maintenance Skill)

本指南为 **Calyx**（基于 Fedora Kinoite 44 的不可变 bootc 操作系统镜像）的开发、配置定制、构建流水线与私有仓库运维提供全套标准作业规程（SOP）。

---

## 1. 架构总览与核心设计哲学

### 1.1 核心技术架构
* **操作系统底座**：Fedora Kinoite 44（KDE Plasma 6, Wayland 原生）。
* **不可变交付 (Bootc Native)**：将整个 OS 打包为标准 OCI 容器镜像，遵循 `bootc` (Container-as-a-system) 范式。
  * `/usr`：系统核心，完全只读，由容器镜像镜像更新覆盖。
  * `/etc`：系统配置文件目录，支持 OSTree 三方合并（Three-way merge）。
  * `/var`：用户数据与可变状态（独立挂载、跨更新持久化）。
* **驱动与内核锁定机制**：
  * Calyx 深度集成专有 NVIDIA 闭源驱动（590+ / 610+ / 615+）。
  * 由于 bootc 镜像构建时必须严格匹配上游内核，采用 **两阶段解耦构建**：
    1. `Containerfile.kmods`：动态识别基础镜像内核，针对特定内核构建驱动并打包为中间镜像 `calyx-kmods:<kernel-ver>`；
    2. `Containerfile`：主镜像通过多阶段构建（`FROM calyx-kmods AS kmods`），将编译好的驱动模块直接注入系统 `/usr/lib/modules`。

### 1.2 双机协作与网络拓扑
* **工作站客户端 (本地开发笔记本)**：
  * 工作目录：`/var/home/jhuang/Workspace/calyx`
  * 职责：编写代码、调试配置、向 GitHub (`origin master` / `origin f44`) 提交代码。
  * 系统部署：通过 `sudo bootc switch` 或 `sudo bootc upgrade` 从私有仓拉取最新构建生效。
* **构建机 / 私有仓宿主机 (`fedora-server`)**：
  * 连接方式：`ssh fedora-server`（工作目录：`~/calyx`）
  * 内网 IP：`192.168.31.4:5000`；本地回环：`127.0.0.1:5000`；外部域名：`registry.elix1r.top`。
  * 自动化构建服务：由 systemd 用户服务与定时器托管（`calyx-build.service` + `calyx-build.timer`），每周日凌晨 04:00 CST 自动执行流水线。
  * 私有仓库数据路径：`/home/jhuang/containers/registry/data`。

---

## 2. 代码仓库结构索引

```text
calyx/
├── Containerfile                  # 主镜像构建定义 (单层执行 + bootc lint 检查)
├── Containerfile.kmods            # 内核驱动模块独立构建容器
├── Taskfile.yml                   # 核心任务管理清单 (go-task 指令集)
├── Taskfile.dist.yml              # 通用 Taskfile 模版
├── .kernel-lock                   # 当前动态锁定的内核版本号缓存
├── scripts/
│   ├── auto-build.sh              # 每周定时自动构建全流水线脚本
│   ├── ensure-kmods.sh            # 动态内核解析与按需构建驱动中间镜像脚本
│   ├── manage-registry-retention.sh # 私有仓库版本淘汰与物理 GC 垃圾回收脚本
│   └── base/                      # 主镜像构建子阶段脚本 (按序在容器内执行)
│       ├── 00_init.sh             # 阶段 0: 初始化环境，配置 DNF5 优化与缓存挂载
│       ├── 01_packages.sh         # 阶段 1: RPM Fusion、官方包安装、第三方源配置与包排除
│       ├── 02_drivers.sh          # 阶段 2: NVIDIA 驱动集成与内核模块部署
│       ├── 03_custom.sh           # 阶段 3: 用户级个性化定制与环境调优
│       ├── 04_configs_services.sh # 阶段 4: 服务激活 (sshd/zram 等) 与配置覆盖
│       └── 05_cleanup.sh          # 阶段 5: 清理仓库配置、清理 /var 与 /run、修复 /opt 软链接
├── source/
│   └── configs/base/              # 覆盖到系统根目录的配置文件树 (与宿主机路径严格对应)
│       ├── etc/
│       │   ├── ssh/sshd_config.d/10-calyx.conf # SSHD 禁用 root 且强制仅密钥登录
│       │   ├── udisks2/mount_options.conf      # NTFS 内核挂载选项优化
│       │   └── rpm-ostreed.conf
│       └── usr/
│           ├── share/flatpak/preinstall.d/     # 开机自动预装 Flatpak 声明
│           └── lib/systemd/system/             # 预装 systemd 自定义服务
└── utils/
    ├── copr-helpers.sh            # 隔离式启用/安装 COPR 包辅助工具
    └── systemd/                   # 定时构建服务单元文件 (部署至 server)
```

---

## 3. 标准操作规程 (SOP)

### SOP-1: 软件包的增加、排除与源管理

所有软件包变更均在 `scripts/base/01_packages.sh` 中完成：

1. **安装 Fedora 官方仓库软件包**：
   直接追加到 `FEDORA_PACKAGES` 数组中，务必附带清晰的中文注释。
   ```bash
   FEDORA_PACKAGES+=(
       your-package-name # 说明该软件包的用途
   )
   ```
2. **安装 RPM Fusion 硬件加速/多媒体包**：
   追加到 `MULTIMEDIA_PACKAGES` 数组。
3. **引入第三方独立源 (如 Chrome / VSCode / Tailscale)**：
   在 `01_packages.sh` 的第三方源段落添加，必须满足两个安全原则：
   * 导入官方 GPG 公钥（`rpm --import`）；
   * Repo 文件默认必须设为 `enabled=0`，安装时使用 `dnf5 -y install --enablerepo=<repo-id> <package>` 单独启用。
4. **排除系统臃肿组件 (`EXCLUDED_PACKAGES`)**：
   若需剔除 Kinoite 自带的非必要组件，追加到 `EXCLUDED_PACKAGES` 数组：
   ```bash
   EXCLUDED_PACKAGES+=(
       unwanted-package # 移除原因说明
   )
   ```
   *注意：脚本使用 `rpm -e --nodeps --noscripts` 静默卸载，以防止上游 scriptlet 在容器内执行失败。*

---

### SOP-2: 系统配置覆盖与服务调整

1. **添加或修改配置文件**：
   * 所有配置必须遵循**无侵入声明式**原则，直接放置在 `source/configs/base/` 对应路径下。
   * 例如覆盖 `/etc/sysctl.d/99-custom.conf`，只需在仓库中创建 `source/configs/base/etc/sysctl.d/99-custom.conf`。
   * 阶段脚本 `04_configs_services.sh` 会在构建时自动递归复制到系统根目录。
2. **SSHD 安全配置规范**：
   * 规则位于 `source/configs/base/etc/ssh/sshd_config.d/10-calyx.conf`。
   * 严格禁止 root 登录（`PermitRootLogin no`）。
   * 严格禁止密码认证（`PasswordAuthentication no`），仅允许普通用户密钥登录。
3. **Flatpak 应用预装配置**：
   * 规则位于 `source/configs/base/usr/share/flatpak/preinstall.d/<app-id>.preinstall`。
   * 结合 `flatpak-preinstall.service`，新机启动或更新后会自动在后台拉取指定的 Flatpak 应用。

---

### SOP-3: 源码提交与多端同步规范

为保持开发分支与生产构建分支的严谨性，修改代码后必须按如下规程同步：

1. **本地工作区提交与检查**：
   ```bash
   cd /var/home/jhuang/Workspace/calyx
   git status
   git add <modified-files>
   git commit -m "feat/fix(scope): description [skip ci]"
   ```
2. **同步至 `master` 与 `f44` 分支并推送到 GitHub**：
   ```bash
   # 如果在 master 上
   git checkout f44
   git cherry-pick <commit-hash>
   git checkout master
   git push origin master f44
   ```
3. **同步构建机 (`fedora-server`)**：
   *注意：除非用户明确要求触发构建，日常代码同步只需拉取代码，切勿手动运行构建任务，留待每周日定时流水线执行。*
   ```bash
   ssh fedora-server "cd ~/calyx && git pull origin master"
   ```

---

### SOP-4: 手动触发镜像构建与合规性检查

当需要立即测试新功能或紧急修复系统时，执行以下命令：

1. **在本地或构建机上手动构建**：
   ```bash
   # 查看任务列表
   task list

   # 一键执行全自动构建与推送 (与定时任务流程完全一致)
   task auto-build
   # 或者分步执行：
   task pull-base       # 拉取最新上游 kinoite:44
   task ensure-kmods    # 检测内核并准备驱动
   task build-nvidia    # 构建主镜像
   task push-nvidia     # 推送到私有仓库并触发版本管理
   ```
2. **关键合规性自检 (bootc container lint)**：
   Calyx 在 `Containerfile` 的最后步骤强制执行：
   ```bash
   bootc container lint --fatal-warnings --no-truncate
   ```
   **必须确保通过 13 项检查且 0 警告 0 错误**。

---

### SOP-5: 私有仓库维护与磁盘存储垃圾回收 (GC)

`fedora-server` 同时承载镜像构建与 Registry 存储，磁盘容量有限，需定期监控与清理：

1. **自动版本保留策略**：
   脚本 `scripts/manage-registry-retention.sh` 预置了版本淘汰规则：
   * `calyx` 系统镜像：最多保留最新的 **3** 个版本；
   * `calyx-kmods` 驱动镜像：最多保留最新的 **2** 个版本。
2. **物理磁盘释放 (Garbage Collection)**：
   Docker Registry 在调用 API 删除 Tag 后，磁盘中的 Blob 实际未被释放，必须触发内部垃圾回收：
   ```bash
   # 在 fedora-server 上执行
   podman exec registry registry garbage-collect /etc/docker/registry/config.yml
   ```
3. **构建机 Podman 悬挂镜像清理**：
   构建流水线结束后，运行以下命令清除临时层：
   ```bash
   # 在 fedora-server 上执行
   podman image prune -f
   ```

---

## 4. 常见排错与避坑指南 (Pitfalls & Troubleshooting)

### 坑 1: `bootc container lint` 失败：`nonempty-run-tmp` 或 `var-tmpfiles`
* **现象**：`Lint warning: nonempty-run-tmp: Found content in /run` 或 `Found content in /var missing systemd tmpfiles.d`。
* **原因**：构建过程中运行了 `dnf5`，残留了 `/var/cache`、`/var/log/dnf5.log` 或 `/run/dnf`。
* **规避规范**：
  * 在 `Containerfile` 中，执行主流水线时必须挂载 tmpfs：
    `--mount=type=tmpfs,dst=/boot --mount=type=tmpfs,dst=/var`
  * 在 `05_cleanup.sh` 中必须显式清除 `/run` 下的临时文件（保留 `/run/systemd` 等挂载锚点）。

### 坑 2: `/opt` 目录的软链接冲突
* **现象**：安装某些商业软件（如 Google Chrome）后，bootc lint 报 `/opt` 路径违背 OSTree 规范。
* **原因**：在 bootc / OSTree 标准中，`/opt` 是指向 `/var/opt` 的软链接；如果在镜像构建中直接向 `/opt` 写入文件，会导致更新时不可变与持久化路径混淆。
* **规避规范**：
  * 安装前若 `/opt` 为软链接，先安全解开：
    ```bash
    if [[ -L /opt ]]; then rm -f /opt && mkdir -p /opt; fi
    ```
  * 在 `05_cleanup.sh` 结尾，若 `/opt` 为空目录，则恢复链接回 `/var/opt`：
    ```bash
    if [[ -d /opt && -z "$(ls -A /opt 2>/dev/null)" ]]; then
        rm -rf /opt && ln -s /var/opt /opt
    fi
    ```

### 坑 3: 标签多重命名导致镜像冗余
* **现象**：`podman images` 中出现 `127.0.0.1:5000/calyx` 和 `registry.elix1r.top/calyx` 双重标签。
* **原因**：`Taskfile.yml` 中曾经同时给构建镜像打上了本地回环 Registry 和公网域名两个前缀。
* **规范**：在服务端，仅打标实际要推送的目标 `{{.REGISTRY}}`（即 `127.0.0.1:5000`），外部客户端拉取时由客户端自行指定域名或局域网 IP，服务端本地无需保留别名。

### 坑 4: 编译产物泄漏进 Git 仓库
* **现象**：Git 仓库体积暴涨，包含 `.ko` 内核驱动或二进制工具。
* **规范**：构建驱动均在 `Containerfile.kmods` 容器内完成并产出镜像，严禁将宿主机编译生成的二进制提取并放置在 `source/configs/base/` 提交。若有残留，执行 `task clean-repo` 清理。

---

## 5. 快速维护命令速查表

| 操作需求 | 执行命令 / 路径 | 备注 |
| :--- | :--- | :--- |
| **查询上游最新内核** | `podman run --rm quay.io/fedora-ostree-desktops/kinoite:44 rpm -q kernel-core` | 确认当前 Kinoite 44 内核 |
| **构建全流程** | `task auto-build` | 自动同步代码、拉取底座、驱动对齐与镜像构建 |
| **查询私有仓镜像列表** | `curl -s http://127.0.0.1:5000/v2/_catalog` | 在 server 上查询已入库仓库 |
| **查询特定仓库版本** | `curl -s http://127.0.0.1:5000/v2/calyx/tags/list` | 查看 calyx 现有 tag |
| **触发私有仓物理 GC** | `podman exec registry registry garbage-collect /etc/docker/registry/config.yml` | 彻底回收删除镜像占用的物理硬盘 |
| **工作站升级系统** | `sudo bootc upgrade && sudo reboot` | 客户端应用最新 Calyx 构建 |
| **工作站系统回滚** | `sudo bootc rollback && sudo reboot` | 遭遇异常时一键退回上一工作快照 |
