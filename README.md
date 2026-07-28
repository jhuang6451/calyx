# Calyx

**English** | [简体中文](./README_zh.md)

**Calyx** is a custom, personal **immutable operating system image** powered by cloud-native container technologies.

Inspired by the build philosophy and engineering paradigms of [Aurora](https://github.com/get-aurora-dev/aurora), Calyx uses upstream [Universal Blue](https://github.com/ublue-os) infrastructure and Fedora Kinoite (KDE Plasma 6) as its core base. It delivers a highly stable, out-of-the-box, and declaratively maintained desktop system experience.

---

## ✨ Features

- **Bootc Native Immutable Architecture**: Built on the `bootc` (Container-as-a-System) paradigm, packaging the entire operating system into an OCI container image. The system core is read-only, natively protecting against accidental tampering and system corruption.
- **Modern Desktop & Multimedia Support**: Integrated KDE Plasma 6 desktop environment, complete hardware video decoding/encoding codecs (VA-API / QSV / NVENC), Google Chrome browser, and a selected set of developer & productivity tools.
- **Out-of-the-Box Performance Tuning**: Unnecessary bloatware and background services removed. Fine-tuned for desktop responsiveness, NVIDIA high-performance/power-saving parameters (PAT & RTD3 D3cold sleep), CPU powercap monitoring (`btop`), and input method integration.
- **Multi-Hardware Variants**: Offers a standard general-purpose image for Intel/AMD graphics as well as an optimized variant for NVIDIA discrete GPUs.

---

## 🚀 Usage Guide

On any system supporting `bootc` (such as Fedora Silverblue / Kinoite / Universal Blue / Bazzite), you can easily switch to and manage Calyx system images using standard `bootc` commands.

### 1. Switching to Calyx Image

#### Standard Variant (Intel / AMD Integrated & Discrete GPUs)
```bash
sudo bootc switch ghcr.io/jhuang6451/calyx:latest
```

#### NVIDIA Variant (Proprietary NVIDIA Driver & Performance Optimizations)
```bash
sudo bootc switch ghcr.io/jhuang6451/calyx:latest-nvidia
```

After switching, reboot your system to load Calyx:
```bash
sudo reboot
```

---

### 2. Daily System Updates & Maintenance

Calyx features a declarative update model. Upgrades are performed safely in the background without affecting your active desktop session:

```bash
# Check for and upgrade to the latest Calyx image
sudo bootc upgrade

# Reboot to apply the new system state
sudo reboot
```

---

### 3. System Rollback

If you encounter any compatibility issues, you can instantly and safely roll back to your previous working system state:

```bash
sudo bootc rollback
```

---

## 📄 License

Distributed under the [MIT License](./LICENSE). Special thanks to [Universal Blue](https://github.com/ublue-os) and [Aurora](https://github.com/get-aurora-dev/aurora) for providing outstanding upstream resources and design patterns.