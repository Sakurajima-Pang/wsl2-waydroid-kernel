# WSL2 Waydroid 内核编译项目版本说明

## 当前版本: v2.0.0

### 版本历史

#### v2.0.0 (2026-04-22)
**重大改进版本**

- **修复了脚本执行问题**: 统一使用 `current_step=$((current_step + 1))` 替代 `((current_step++))`，避免在 `set -e` 模式下值为0时返回退出码1导致脚本意外退出
- **自动利用 WSL 虚拟硬盘**: 
  - 03-build-kernel.sh 现在会自动检测项目是否在 WSL 虚拟硬盘 (ext4) 上
  - 如果项目在 Windows 文件系统 (9p) 上，自动切换到 `$HOME/.wsl-waydroid-build` 目录
  - 提供清晰的指导，建议用户将项目复制到 WSL 虚拟硬盘上
- **支持 KERNEL_DIR 环境变量**: 允许用户通过环境变量指定内核源码目录
- **修复了 ASHMEM 配置问题**: 根据内核版本自动判断是否启用 ASHMEM（内核 < 5.18 启用，>= 5.18 使用 memfd 替代）
- **改进了输入读取**: 统一使用 `read -r REPLY < /dev/tty 2>/dev/null || read -r REPLY` 模式，提高兼容性
- **更新了版本号**: 所有脚本版本号更新为 v2.0.0
- **改进了验证脚本**: 06-verify.sh 增加了 binderfs 和 memfd 检查
- **改进了 Waydroid 安装**: 05-install-waydroid.sh 增加了 setup_binderfs 函数，自动挂载 binderfs 并创建符号链接
- **删除了代理配置相关代码**: 由于 Clash TUN 模式已配置，WSL 中不需要额外代理配置
- **清理了无用文件**: 删除了备份目录和内核源码目录等临时文件

#### v1.0.0 (初始版本)
- 基础功能实现
- 包含 7 个脚本：01-check-env.sh, 02-install-deps.sh, 03-build-kernel.sh, 04-install-kernel.sh, 05-install-waydroid.sh, 06-verify.sh, 99-rollback.sh

### 已知问题与解决方案

#### 1. 文件系统大小写敏感性问题
**问题**: Windows NTFS 默认不区分大小写，导致内核源码编译时出现头文件冲突
**解决方案**:
- **推荐**: 将项目复制到 WSL 虚拟硬盘（ext4 文件系统）上
  ```bash
  cp -r /mnt/d/番茄小说/wsl2-waydroid-kernel ~/wsl2-waydroid-kernel
  cd ~/wsl2-waydroid-kernel/scripts
  bash 03-build-kernel.sh
  ```
- 脚本会自动检测文件系统类型，如果不在 ext4 上会给出警告和建议
- 如果坚持在 Windows 文件系统上运行，脚本会自动切换到 `$HOME/.wsl-waydroid-build` 目录
- 也可以手动设置 KERNEL_DIR 环境变量指向 ext4 分区中的目录

#### 2. ASHMEM 在 5.18+ 内核中已移除
**问题**: Linux 5.18+ 内核已移除 ASHMEM，使用 memfd 替代
**解决方案**: 脚本会根据内核版本自动判断是否启用 ASHMEM

#### 3. 内核路径包含中文字符
**问题**: WSL 无法加载中文路径中的自定义内核
**解决方案**: 内核自动复制到英文路径 `C:\Users\<用户名>\wsl2-waydroid-kernel\`

### 使用说明

#### 标准执行流程
```bash
bash 01-check-env.sh
bash 02-install-deps.sh
bash 03-build-kernel.sh
bash 04-install-kernel.sh
bash 05-install-waydroid.sh
bash 06-verify.sh
```

#### 在 WSL 虚拟硬盘上编译（推荐）
```bash
# 将项目复制到 WSL 虚拟硬盘（ext4）上
cp -r /mnt/d/番茄小说/wsl2-waydroid-kernel ~/wsl2-waydroid-kernel
cd ~/wsl2-waydroid-kernel/scripts

# 直接运行编译脚本
bash 03-build-kernel.sh
```

#### 使用 ext4 虚拟磁盘编译（备选）
如果 WSL 虚拟硬盘空间不足，可以创建额外的 ext4 虚拟磁盘：
```bash
# 创建并挂载 ext4 虚拟磁盘
mkdir -p ~/wsl-kernel-build
dd if=/dev/zero of=~/wsl-kernel-build/kernel-build.ext4 bs=1M count=20480
mkfs.ext4 ~/wsl-kernel-build/kernel-build.ext4
mkdir -p ~/wsl-kernel-build/mnt
sudo mount -o loop ~/wsl-kernel-build/kernel-build.ext4 ~/wsl-kernel-build/mnt

# 设置环境变量并编译
export KERNEL_DIR=~/wsl-kernel-build/mnt/WSL2-Linux-Kernel
bash 03-build-kernel.sh
```

#### 跳过确认提示（自动化）
```bash
export SKIP_CONFIRM=1
bash 03-build-kernel.sh
bash 04-install-kernel.sh
```

### 文件结构
```
wsl2-waydroid-kernel/
├── scripts/
│   ├── 01-check-env.sh      # 环境检查
│   ├── 02-install-deps.sh   # 安装依赖
│   ├── 03-build-kernel.sh   # 编译内核
│   ├── 04-install-kernel.sh # 安装内核
│   ├── 05-install-waydroid.sh # 安装 Waydroid
│   ├── 06-verify.sh         # 验证安装
│   └── 99-rollback.sh       # 回滚工具
├── build/                    # 构建输出目录
├── logs/                     # 日志目录
├── VERSION.md               # 本文件
└── 内核编译部署总结.md       # 经验总结文档
```

### 依赖
- WSL2
- Ubuntu 22.04/24.04 LTS (或其他兼容发行版)
- 20GB+ 磁盘空间
- 4GB+ 内存

### 参考链接
- [WSL2-Linux-Kernel GitHub](https://github.com/microsoft/WSL2-Linux-Kernel)
- [Waydroid 官方文档](https://docs.waydro.id/)
