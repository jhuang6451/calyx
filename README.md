# Calyx

**Calyx** 是一个基于云原生容器技术打造的**个人定制化不可变操作系统镜像（Immutable OS Image）**。

项目借鉴并参考了 [Aurora](https://github.com/get-aurora-dev/aurora) 的构建哲学与工程范式，以上游 [Universal Blue](https://github.com/ublue-os) 基础设施以及 Fedora Kinoite (KDE Plasma) 为核心底座，为个人桌面环境提供高稳定、开箱即用且声明式维护的系统体验。

---

## ✨ 核心特性

- **不可变架构 (Bootc Native)**：基于 `bootc` (Container-as-a-system) 理念，将整个操作系统打包为 OCI 容器镜像。系统核心只读，原生防篡改与防系统损坏。
- **现代化桌面与多媒体**：集成 KDE Plasma 6 桌面环境、完整版音视频硬件编解码支持（VA-API / QSV / NVENC）、Google Chrome 浏览器及一系列选定的开发与效率工具。
- **开箱即用与极简优化**：剔除冗余的内置软件与后台服务，针对桌面响应速度、硬件功耗读取及输入法体验进行了针对性调优。
- **多硬件版本支持**：提供 Intel/AMD 标准通用版本以及专为 NVIDIA 独立显卡优化的驱动版本。

---

## 🚀 镜像使用指南

在任何支持 `bootc` 的操作系统（如 Fedora Silverblue / Kinoite / Universal Blue / Bazzite）中，均可通过标准 `bootc` 命令切换与管理 Calyx 系统镜像。

### 1. 切换至 Calyx 系统镜像

#### 标准通用版 (Intel / AMD 核显及独显)
```bash
sudo bootc switch ghcr.io/jhuang6451/calyx:latest
```

#### NVIDIA 显卡驱动版
```bash
sudo bootc switch ghcr.io/jhuang6451/calyx:latest-nvidia
```

切换完成后，重启计算机即可载入全新的 Calyx 系统：
```bash
sudo reboot
```

---

### 2. 系统日常更新与维护

Calyx 系统采用声明式更新机制，升级过程在后台完成且不会影响当前运行中的应用：

```bash
# 检查并更新至最新的 Calyx 镜像版本
sudo bootc upgrade

# 更新完成后重启应用新版本
sudo reboot
```

---

### 3. 版本回滚 (Rollback)

若遇到任何兼容性问题，可随时一键安全回滚至升级前的工作状态：

```bash
sudo bootc rollback
```

---

## 📄 开源许可

本项目遵循 MIT 开源许可协议。感谢 [Universal Blue](https://github.com/ublue-os) 与 [Aurora](https://github.com/get-aurora-dev/aurora) 社区提供的优秀上游资源与范式支持。