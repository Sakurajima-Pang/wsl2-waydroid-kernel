# WSL2 Waydroid 内核编译完整指南

## 项目版本
- **版本**: v1.0.0
- **更新日期**: 2026-04-21
- **作者**: AI Assistant

---

## 目录

1. [项目概述](#项目概述)
2. [环境要求](#环境要求)
3. [文件结构](#文件结构)
4. [快速开始](#快速开始)
5. [详细步骤](#详细步骤)
6. [故障排除](#故障排除)
7. [版本历史](#版本历史)

---

## 项目概述

本项目提供一套完整的 Bash 脚本，用于在 WSL2 中编译支持 Waydroid 的自定义 Linux 内核。Waydroid 是一个基于容器的 Android 运行环境，需要特定的内核模块支持。

### 目标

- 为 WSL2 编译支持 Waydroid 的自定义 Linux 内核
- 提供自动化、可重复、安全的安装流程
- 支持一键回滚到默认配置

### 需要的内核模块

```
CONFIG_ANDROID=y
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDERFS=y
CONFIG_ASHMEM=y
CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"
CONFIG_MEMCG=y
CONFIG_CGROUP_DEVICE=y
```

---

## 环境要求

### 系统要求

| 项目 | 最低要求 | 推荐配置 |
|------|----------|----------|
| Windows 版本 | Windows 10 21H2+ | Windows 11 最新版 |
| WSL 版本 | WSL2 | WSL2 最新版 |
| WSL 发行版 | Ubuntu 20.04 | Ubuntu 22.04/24.04 LTS |
| 磁盘空间 | 15GB 空闲 | 20GB+ 空闲 |
| 内存 | 4GB | 8GB+ |
| 网络 | 可访问 GitHub | 稳定网络连接 |

### 时间预估

| 步骤 | 预估时间 |
|------|----------|
| 环境检查 | 1-2 分钟 |
| 依赖安装 | 5-10 分钟 |
| 内核编译 | 30-60 分钟 |
| 内核安装 | 2-5 分钟 |
| Waydroid 安装 | 10-20 分钟 |
| 验证 | 1-2 分钟 |
| **总计** | **50-100 分钟** |

---

## 文件结构

```
wsl2-waydroid-kernel/
├── GUIDE.md                    # 本指南文档
├── README.md                   # 项目简介
├── CHANGELOG.md                # 版本变更日志
├── scripts/
│   ├── 01-check-env.sh         # 环境检查脚本
│   ├── 02-install-deps.sh      # 依赖安装脚本
│   ├── 03-build-kernel.sh      # 内核编译脚本
│   ├── 04-install-kernel.sh    # 内核安装脚本
│   ├── 05-install-waydroid.sh  # Waydroid 安装脚本
│   ├── 06-verify.sh            # 验证脚本
│   └── 99-rollback.sh          # 回滚脚本
└── logs/                       # 日志目录（运行时创建）
```

---

## 快速开始

### 1. 克隆或下载项目

```bash
# 在 WSL 中执行
cd ~
git clone <repository-url> wsl2-waydroid-kernel
cd wsl2-waydroid-kernel/scripts
```

### 2. 按顺序执行脚本

```bash
# 步骤 1: 环境检查
bash 01-check-env.sh

# 步骤 2: 安装依赖
bash 02-install-deps.sh

# 步骤 3: 编译内核（耗时最长）
bash 03-build-kernel.sh

# 步骤 4: 安装内核
bash 04-install-kernel.sh

# 步骤 5: 安装 Waydroid
bash 05-install-waydroid.sh

# 步骤 6: 验证安装
bash 06-verify.sh
```

### 3. 启动 Waydroid

```bash
# 启动 Waydroid 会话
waydroid session start

# 在新终端中启动图形界面
waydroid show-full-ui
```

---

## 详细步骤

### 步骤 1: 环境检查 (01-check-env.sh)

**功能**: 检查系统环境是否满足编译要求

**检查项**:
- WSL 版本（必须 WSL2）
- 发行版信息
- 磁盘空间（需 15GB+）
- 网络连接（GitHub 可访问性）
- 系统架构

**输出**: 环境状态报告

**示例输出**:
```
========================================
   WSL2 Waydroid 环境检查报告
========================================
[✓] WSL 版本: 2
[✓] 发行版: Ubuntu 22.04.3 LTS
[✓] 架构: x86_64
[✓] 磁盘空间: 45.2GB 可用 (需要 15GB)
[✓] GitHub 连接: 正常
[✓] 内核版本: 5.15.133.1-microsoft-standard-WSL2
----------------------------------------
状态: 环境检查通过
========================================
```

---

### 步骤 2: 安装依赖 (02-install-deps.sh)

**功能**: 安装编译内核所需的依赖包

**安装内容**:
- build-essential
- flex, bison
- libssl-dev
- libelf-dev
- bc
- dwarves
- 其他编译工具

**代理配置**:
脚本会自动检测并配置代理（如需要）

**示例输出**:
```
[INFO] 更新软件包列表...
[INFO] 安装编译依赖...
[INFO] 已安装: build-essential
[INFO] 已安装: flex bison
...
[SUCCESS] 所有依赖安装完成
```

---

### 步骤 3: 编译内核 (03-build-kernel.sh)

**功能**: 克隆并编译 WSL2 内核

**流程**:
1. 克隆微软 WSL2 内核源码
2. 复制当前内核配置
3. 应用 Waydroid 所需的配置补丁
4. 编译内核（使用多线程加速）
5. 输出编译后的内核文件

**配置修改**:
启用以下内核选项：
```
CONFIG_ANDROID=y
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDERFS=y
CONFIG_ASHMEM=y
CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"
CONFIG_MEMCG=y
CONFIG_CGROUP_DEVICE=y
```

**输出**:
- 编译后的内核镜像: `arch/x86/boot/bzImage`
- 内核模块目录

**示例输出**:
```
[INFO] 克隆 WSL2 内核源码...
[INFO] 复制内核配置...
[INFO] 应用 Waydroid 配置补丁...
[INFO] 开始编译内核（使用 8 线程）...
[INFO] 编译进度: [##########] 100%
[SUCCESS] 内核编译完成
[SUCCESS] 内核文件: /home/user/wsl2-waydroid-kernel/build/bzImage
```

---

### 步骤 4: 安装内核 (04-install-kernel.sh)

**功能**: 安装编译好的内核到 WSL

**流程**:
1. 备份当前内核（可选）
2. 复制新内核到 WSL 目录
3. 创建/编辑 Windows 端 `.wslconfig`
4. 重启 WSL
5. 验证新内核生效

**Windows 配置**:
脚本会在 Windows 用户目录创建 `.wslconfig`:
```ini
[wsl2]
kernel=C:\Users\<用户名>\wsl2-waydroid-kernel\bzImage-waydroid
```

**注意**: 此步骤需要管理员权限

**示例输出**:
```
[INFO] 备份当前内核...
[INFO] 安装新内核...
[INFO] 配置 .wslconfig...
[INFO] 重启 WSL...
[INFO] 验证新内核...
[SUCCESS] 内核安装成功
[SUCCESS] 新内核版本: 5.15.133.1-microsoft-standard-WSL2-waydroid
```

---

### 步骤 5: 安装 Waydroid (05-install-waydroid.sh)

**功能**: 安装 Waydroid 及 Android 系统镜像

**流程**:
1. 添加 Waydroid 官方仓库
2. 安装 Waydroid 及依赖
3. 初始化 Waydroid 容器
4. 下载 Android 系统镜像

**系统镜像**:
- 默认下载 LineageOS 镜像
- 可选择 GAPPS 版本（含 Google 服务）

**示例输出**:
```
[INFO] 添加 Waydroid 仓库...
[INFO] 安装 Waydroid...
[INFO] 初始化 Waydroid 容器...
[INFO] 下载 Android 系统镜像...
[PROGRESS] 下载进度: [##########] 100%
[SUCCESS] Waydroid 安装完成
```

---

### 步骤 6: 验证 (06-verify.sh)

**功能**: 验证所有组件是否正确安装和运行

**验证项**:
- [✓] 内核模块是否加载
- [✓] binder 设备是否存在 (`/dev/binder`, `/dev/hwbinder`, `/dev/vndbinder`)
- [✓] ashmem 设备是否存在
- [✓] Waydroid 服务状态
- [✓] 容器状态

**示例输出**:
```
========================================
   Waydroid 安装验证报告
========================================
[✓] Android 内核模块已加载
[✓] binder 设备存在: /dev/binder
[✓] hwbinder 设备存在: /dev/hwbinder
[✓] vndbinder 设备存在: /dev/vndbinder
[✓] ashmem 设备存在: /dev/ashmem
[✓] Waydroid 服务运行中
[✓] Waydroid 容器已初始化
----------------------------------------
状态: 所有检查通过 ✓
========================================
```

---

### 回滚 (99-rollback.sh)

**功能**: 恢复到默认配置

**选项**:
1. 恢复默认内核
2. 清理编译产物
3. 卸载 Waydroid（可选）

**使用场景**:
- 新内核出现问题
- 需要释放磁盘空间
- 不再使用 Waydroid

**示例输出**:
```
[WARNING] 即将执行回滚操作
[INFO] 恢复默认内核配置...
[INFO] 清理编译产物...
[INFO] 重启 WSL...
[SUCCESS] 回滚完成，系统已恢复到默认状态
```

---

## 故障排除

### 常见问题

#### 1. 编译失败：内存不足

**症状**: 编译过程中出现 `out of memory` 错误

**解决**:
```bash
# 创建 swap 文件
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

#### 2. 内核模块未加载

**症状**: Waydroid 启动失败，提示 binder 设备不存在

**解决**:
```bash
# 手动加载模块
sudo modprobe binder_linux devices="binder,hwbinder,vndbinder"
sudo modprobe ashmem_linux

# 验证
ls -la /dev/binder /dev/ashmem
```

#### 3. Waydroid 无法启动图形界面

**症状**: `waydroid show-full-ui` 无响应

**解决**:
```bash
# 检查 Weston/Xwayland
sudo apt install weston

# 设置显示环境
export DISPLAY=:0

# 重启 Waydroid
waydroid session stop
waydroid session start
```

#### 4. 网络连接问题

**症状**: 无法克隆内核源码或下载镜像

**解决**:
- 检查代理配置
- 使用镜像源
- 手动下载后放置到指定目录

#### 5. WSL 无法启动

**症状**: 安装新内核后 WSL 无法启动

**解决**:
```powershell
# 在 PowerShell 中执行
wsl --shutdown
# 删除 .wslconfig 中的 kernel 配置
# 重启 WSL
wsl
```

---

## 版本历史

### v1.0.0 (2026-04-21)

- 初始版本发布
- 包含 7 个独立脚本
- 支持 Ubuntu 22.04/24.04 LTS
- 完整的错误处理和日志记录
- 彩色输出和进度提示

---

## 参考资源

- [WSL2 内核源码](https://github.com/microsoft/WSL2-Linux-Kernel)
- [Waydroid 官方文档](https://docs.waydro.id/)
- [Waydroid GitHub](https://github.com/waydroid/waydroid)
- [WSL 官方文档](https://docs.microsoft.com/zh-cn/windows/wsl/)

---

## 许可证

本项目脚本遵循 MIT 许可证。

---

## 贡献

欢迎提交 Issue 和 Pull Request 来改进本项目。
