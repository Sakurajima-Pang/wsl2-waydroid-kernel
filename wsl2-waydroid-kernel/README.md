# WSL2 Waydroid 内核编译项目

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

一套完整的 Bash 脚本，用于在 WSL2 中编译支持 Waydroid 的自定义 Linux 内核。

## 项目简介

Waydroid 是一个基于容器的 Android 运行环境，可以在 Linux 系统上运行完整的 Android 系统。由于 WSL2 默认内核不包含 Waydroid 所需的特定内核模块（如 binder、ashmem），因此需要编译自定义内核。

本项目提供自动化脚本，简化整个编译和安装过程。

## 功能特性

- 完整的自动化流程，从环境检查到 Waydroid 安装
- 详细的日志记录和错误处理
- 彩色输出和进度提示
- 支持代理配置
- 一键回滚功能
- 详细的故障排除指南

## 系统要求

| 项目 | 最低要求 | 推荐配置 |
|------|----------|----------|
| Windows 版本 | Windows 10 21H2+ | Windows 11 最新版 |
| WSL 版本 | WSL2 | WSL2 最新版 |
| WSL 发行版 | Ubuntu 20.04 | Ubuntu 22.04/24.04 LTS |
| 磁盘空间 | 15GB 空闲 | 20GB+ 空闲 |
| 内存 | 4GB | 8GB+ |

## 快速开始

### 1. 下载项目

```bash
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

# 步骤 3: 编译内核（耗时 30-60 分钟）
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

## 文件结构

```
wsl2-waydroid-kernel/
├── GUIDE.md                    # 完整指南文档
├── README.md                   # 本文件
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

## 脚本说明

### 01-check-env.sh
检查系统环境是否满足编译要求，包括：
- WSL 版本验证
- 磁盘空间检查
- 网络连接测试
- 系统架构确认

### 02-install-deps.sh
安装编译内核所需的依赖包：
- build-essential、flex、bison
- libssl-dev、libelf-dev
- bc、dwarves、git 等

### 03-build-kernel.sh
编译 WSL2 内核：
- 克隆微软 WSL2 内核源码
- 配置内核选项（启用 binder、ashmem 等）
- 编译内核（支持多线程加速）

### 04-install-kernel.sh
安装编译好的内核：
- 备份当前配置
- 复制内核到 Windows
- 配置 `.wslconfig`
- 重启 WSL

### 05-install-waydroid.sh
安装 Waydroid：
- 添加 Waydroid 官方仓库
- 安装 Waydroid 及依赖
- 初始化容器并下载 Android 镜像

### 06-verify.sh
验证安装结果：
- 检查内核模块
- 验证 binder 设备
- 检查 Waydroid 服务状态

### 99-rollback.sh
回滚到默认配置：
- 恢复默认内核
- 清理编译产物
- 卸载 Waydroid（可选）

## 时间预估

| 步骤 | 预估时间 |
|------|----------|
| 环境检查 | 1-2 分钟 |
| 依赖安装 | 5-10 分钟 |
| 内核编译 | 30-60 分钟 |
| 内核安装 | 2-5 分钟 |
| Waydroid 安装 | 10-20 分钟 |
| 验证 | 1-2 分钟 |
| **总计** | **50-100 分钟** |

## 故障排除

### 编译失败：内存不足

```bash
# 创建 swap 文件
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### binder 设备不存在

```bash
# 手动加载模块
sudo modprobe binder_linux devices="binder,hwbinder,vndbinder"
sudo modprobe ashmem_linux
```

### Waydroid 无法启动图形界面

```bash
# 安装 Weston
sudo apt install weston
export DISPLAY=:0
waydroid session stop
waydroid session start
```

更多故障排除信息请查看 [GUIDE.md](GUIDE.md)。

## 版本历史

查看 [CHANGELOG.md](CHANGELOG.md) 了解详细的版本变更历史。

### 当前版本: v1.0.0

- 初始版本发布
- 包含 7 个独立脚本
- 支持 Ubuntu 22.04/24.04 LTS
- 完整的错误处理和日志记录

## 贡献

欢迎提交 Issue 和 Pull Request 来改进本项目。

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交变更 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

## 许可证

本项目遵循 MIT 许可证。

## 致谢

- [Microsoft WSL2-Linux-Kernel](https://github.com/microsoft/WSL2-Linux-Kernel)
- [Waydroid](https://waydro.id/)
- [Waydroid 文档](https://docs.waydro.id/)

## 相关链接

- [WSL 官方文档](https://docs.microsoft.com/zh-cn/windows/wsl/)
- [Waydroid GitHub](https://github.com/waydroid/waydroid)
- [项目问题反馈](../../issues)

---

**注意**: 本项目仅供学习和研究使用。使用本项目产生的任何风险和后果由用户自行承担。
