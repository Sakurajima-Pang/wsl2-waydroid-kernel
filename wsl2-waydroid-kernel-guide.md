# WSL2 Waydroid 内核编译完整指南

## 目录
1. [环境准备](#环境准备)
2. [编译步骤](#编译步骤)
3. [自动化脚本](#自动化脚本)
4. [验证方法](#验证方法)
5. [回滚方案](#回滚方案)
6. [常见问题排查](#常见问题排查)

---

## 环境准备

### 系统要求
- Windows 10 版本 2004 及以上 (Build 19041+) 或 Windows 11
- WSL2 已安装并配置
- 至少 20GB 可用磁盘空间
- 稳定的网络连接

### 在 WSL2 Ubuntu 中安装依赖

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装编译依赖
sudo apt install -y \
    build-essential \
    flex \
    bison \
    libssl-dev \
    libelf-dev \
    libncurses-dev \
    autoconf \
    libudev-dev \
    libtool \
    dwarves \
    bc \
    git \
    wget \
    python3 \
    python3-pip
```

---

## 编译步骤

### 步骤 1: 创建工作目录

```bash
mkdir -p ~/wsl2-kernel-build
cd ~/wsl2-kernel-build
```

### 步骤 2: 下载 WSL2 内核源码

```bash
# 获取当前 WSL2 内核版本
WSL_VERSION=$(uname -r)
echo "当前 WSL2 内核版本: $WSL_VERSION"

# 克隆微软 WSL2 内核仓库
git clone https://github.com/microsoft/WSL2-Linux-Kernel.git
cd WSL2-Linux-Kernel

# 切换到与当前 WSL2 版本匹配的标签
# 例如，如果 uname -r 显示 5.15.90.1-microsoft-standard-WSL2
git tag | grep "linux-msft-wsl-" | tail -20

# 选择最接近的版本
# 注意：先查看可用的标签，然后手动选择匹配版本
git checkout linux-msft-wsl-5.15.90.1  # 替换为实际的版本号
```

### 步骤 3: 配置内核

```bash
# 复制当前 WSL2 的配置作为基础
# 从运行的 WSL2 中提取配置（如果存在）
if [ -f /proc/config.gz ]; then
    zcat /proc/config.gz > .config
else
    # 使用仓库中的默认配置
    cp Microsoft/config-wsl .config
fi

# 确保配置是最新的
make oldconfig
```

### 步骤 4: 启用 Waydroid 所需的内核模块

```bash
# 使用脚本启用必要的配置选项
./scripts/config --enable CONFIG_ANDROID
./scripts/config --enable CONFIG_ANDROID_BINDER_IPC
./scripts/config --enable CONFIG_ANDROID_BINDERFS
./scripts/config --enable CONFIG_ASHMEM
./scripts/config --enable CONFIG_MEMCG
./scripts/config --enable CONFIG_CGROUP_DEVICE

# 添加binder设备配置（字符串类型配置，scripts/config不支持字符串类型）
sed -i '/^CONFIG_ANDROID_BINDER_DEVICES=/d' .config
echo 'CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"' >> .config

# 验证配置
grep -E "CONFIG_ANDROID|CONFIG_ASHMEM|CONFIG_BINDER" .config
```

### 步骤 5: 编译内核

```bash
# 清理之前的编译（首次编译可跳过）
# make clean

# 编译内核
# -j$(nproc) 使用所有 CPU 核心
# 编译时间：30-60 分钟，取决于硬件性能
make -j$(nproc) 2>&1 | tee build.log

# 编译完成后，内核镜像位置
# arch/x86/boot/bzImage
```

### 步骤 6: 安装内核模块

```bash
# 安装内核模块到指定目录
sudo make modules_install

# 或者安装到自定义目录
# make INSTALL_MOD_PATH=$HOME/wsl2-modules modules_install
```

### 步骤 7: 复制内核到 Windows

```bash
# 创建 Windows 可访问的目录
mkdir -p /mnt/c/wsl2-kernel

# 复制编译好的内核
cp arch/x86/boot/bzImage /mnt/c/wsl2-kernel/bzImage-waydroid

# 复制配置文件（便于后续参考）
cp .config /mnt/c/wsl2-kernel/config-waydroid

echo "内核已复制到: C:\wsl2-kernel\bzImage-waydroid"
```

### 步骤 8: 配置 WSL2 使用新内核

在 Windows PowerShell 或 CMD 中执行：

```powershell
# 创建或编辑 WSL 配置文件
notepad $env:USERPROFILE\.wslconfig
```

添加以下内容：

```ini
[wsl2]
kernel=C:\\wsl2-kernel\\bzImage-waydroid
memory=8GB
processors=4
swap=2GB
localhostForwarding=true
```

### 步骤 9: 重启 WSL2

```powershell
# 在 Windows PowerShell 中执行
wsl --shutdown

# 重新启动 WSL2
wsl
```

---

## 自动化脚本

### 一键编译脚本: `build-wsl2-waydroid-kernel.sh`

```bash
#!/bin/bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否在 WSL2 中运行
check_wsl2() {
    if ! grep -q "microsoft" /proc/version && ! grep -q "WSL" /proc/version; then
        log_error "此脚本必须在 WSL2 环境中运行"
        exit 1
    fi
    log_info "WSL2 环境检测通过"
}

# 检查磁盘空间
check_disk_space() {
    local available=$(df /home | tail -1 | awk '{print $4}')
    local required=$((20 * 1024 * 1024)) # 20GB in KB
    
    if [ "$available" -lt "$required" ]; then
        log_error "磁盘空间不足。需要至少 20GB，当前可用: $((available / 1024 / 1024))GB"
        exit 1
    fi
    log_info "磁盘空间检查通过"
}

# 安装依赖
install_dependencies() {
    log_info "安装编译依赖..."
    sudo apt update
    sudo apt install -y \
        build-essential \
        flex \
        bison \
        libssl-dev \
        libelf-dev \
        libncurses-dev \
        autoconf \
        libudev-dev \
        libtool \
        dwarves \
        bc \
        git \
        wget \
        python3 \
        python3-pip
    log_info "依赖安装完成"
}

# 下载内核源码
download_kernel() {
    log_info "下载 WSL2 内核源码..."
    
    mkdir -p ~/wsl2-kernel-build
    cd ~/wsl2-kernel-build
    
    if [ -d "WSL2-Linux-Kernel" ]; then
        log_warn "内核源码目录已存在，更新中..."
        cd WSL2-Linux-Kernel
        git fetch --tags
    else
        git clone https://github.com/microsoft/WSL2-Linux-Kernel.git
        cd WSL2-Linux-Kernel
    fi
    
    # 获取匹配的版本
    local kernel_version=$(uname -r | cut -d'-' -f1)
    local tag="linux-msft-wsl-${kernel_version}"
    
    if git tag | grep -q "^${tag}$"; then
        git checkout "${tag}"
        log_info "已切换到标签: ${tag}"
    else
        log_warn "未找到精确匹配的版本，使用最新版本"
        local latest_tag=$(git tag | grep "linux-msft-wsl-" | sort -V | tail -1)
        git checkout "${latest_tag}"
        log_info "已切换到最新标签: ${latest_tag}"
    fi
}

# 配置内核
configure_kernel() {
    log_info "配置内核..."
    
    # 使用当前配置
    if [ -f /proc/config.gz ]; then
        zcat /proc/config.gz > .config
    else
        cp Microsoft/config-wsl .config
    fi
    
    # 启用 Waydroid 所需模块
    log_info "启用 Waydroid 内核模块..."
    
    # 布尔值配置
    declare -a configs=(
        "CONFIG_ANDROID"
        "CONFIG_ANDROID_BINDER_IPC"
        "CONFIG_ANDROID_BINDERFS"
        "CONFIG_ASHMEM"
        "CONFIG_BINDERFS"
        "CONFIG_MEMCG"
        "CONFIG_CGROUP_DEVICE"
    )
    
    for cfg in "${configs[@]}"; do
        # 删除旧配置并添加新配置
        sed -i "/^${cfg}=/d" .config
        echo "${cfg}=y" >> .config
    done
    
    # 添加binder设备配置（字符串类型）
    sed -i '/^CONFIG_ANDROID_BINDER_DEVICES=/d' .config
    echo 'CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"' >> .config
    
    # 更新配置
    make olddefconfig
    
    log_info "内核配置完成"
    
    # 显示关键配置
    log_info "验证关键配置:"
    grep -E "CONFIG_ANDROID|CONFIG_ASHMEM|CONFIG_BINDER" .config | head -10
}

# 编译内核
compile_kernel() {
    log_info "开始编译内核..."
    log_warn "这可能需要 30-60 分钟，请耐心等待..."
    
    local start_time=$(date +%s)
    
    make -j$(nproc) 2>&1 | tee build.log
    
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        log_error "内核编译失败，请检查 build.log"
        exit 1
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_info "内核编译完成，耗时: $((duration / 60)) 分 $((duration % 60)) 秒"
}

# 安装内核
install_kernel() {
    log_info "安装内核..."
    
    # 创建 Windows 目录
    mkdir -p /mnt/c/wsl2-kernel
    
    # 复制内核
    cp arch/x86/boot/bzImage /mnt/c/wsl2-kernel/bzImage-waydroid
    cp .config /mnt/c/wsl2-kernel/config-waydroid
    
    log_info "内核已安装到 C:\\wsl2-kernel\\bzImage-waydroid"
}

# 生成 WSL 配置
generate_wsl_config() {
    log_info "生成 WSL 配置文件..."
    
    cat > /mnt/c/wsl2-kernel/wslconfig-template.txt << 'EOF'
[wsl2]
kernel=C:\\wsl2-kernel\\bzImage-waydroid
memory=8GB
processors=4
swap=2GB
localhostForwarding=true
EOF

    log_info "WSL 配置模板已保存到 C:\\wsl2-kernel\\wslconfig-template.txt"
    log_info "请手动将此内容添加到 %USERPROFILE%\\.wslconfig"
}

# 主函数
main() {
    log_info "=== WSL2 Waydroid 内核编译脚本 ==="
    log_info "开始时间: $(date)"
    
    check_wsl2
    check_disk_space
    install_dependencies
    download_kernel
    configure_kernel
    compile_kernel
    install_kernel
    generate_wsl_config
    
    log_info "=== 编译完成 ==="
    log_info "请按照以下步骤完成配置:"
    echo ""
    echo "1. 在 Windows PowerShell 中执行:"
    echo "   notepad \$env:USERPROFILE\\.wslconfig"
    echo ""
    echo "2. 添加以下内容:"
    cat /mnt/c/wsl2-kernel/wslconfig-template.txt
    echo ""
    echo "3. 重启 WSL2:"
    echo "   wsl --shutdown"
    echo "   wsl"
    echo ""
    echo "4. 验证新内核:"
    echo "   uname -r"
    echo ""
}

# 错误处理
trap 'log_error "脚本执行出错，行号: $LINENO"' ERR

# 运行主函数
main "$@"
```

---

## 验证方法

### 1. 确认新内核已生效

```bash
# 检查当前内核版本
uname -r

# 应该显示自定义编译的版本，例如:
# 5.15.90.1-microsoft-standard-WSL2
```

```bash
# 检查内核编译时间（确认是新内核）
cat /proc/version

# 验证关键模块是否已启用
if [ -f /boot/config-$(uname -r) ]; then
    grep -E "CONFIG_ANDROID|CONFIG_ASHMEM|CONFIG_BINDER" /boot/config-$(uname -r)
elif [ -f /proc/config.gz ]; then
    zcat /proc/config.gz | grep -E "CONFIG_ANDROID|CONFIG_ASHMEM|CONFIG_BINDER"
else
    echo "无法找到内核配置文件"
fi
```

### 2. 验证 Waydroid 支持

```bash
# 检查 binder 设备
ls -la /dev/binder*

# 应该显示:
# /dev/binder
# /dev/hwbinder
# /dev/vndbinder

# 检查 binderfs
ls -la /dev/binderfs/

# 检查 ashmem
ls -la /dev/ashmem

# 检查内核模块
lsmod | grep -E "binder|ashmem"
```

### 3. 安装和测试 Waydroid

```bash
# 安装 Waydroid
sudo apt install -y waydroid

# 初始化 Waydroid（下载 LineageOS 镜像）
# 如果需要包含 Google Play 服务，添加 -g 参数
sudo waydroid init
# 或带 Google Play: sudo waydroid init -g

# 启动 Waydroid 服务
sudo systemctl start waydroid-container

# 检查 Waydroid 状态
waydroid status

# 启动 Waydroid
waydroid show-full-ui
```

### 4. 完整验证脚本: `verify-waydroid.sh`

```bash
#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== WSL2 Waydroid 验证脚本 ==="
echo ""

# 检查内核
echo "1. 检查内核版本:"
uname -r
echo ""

# 检查 binder 设备
echo "2. 检查 Binder 设备:"
if ls /dev/binder* 2>/dev/null; then
    echo -e "${GREEN}✓ Binder 设备存在${NC}"
else
    echo -e "${RED}✗ Binder 设备不存在${NC}"
fi
echo ""

# 检查 ashmem
echo "3. 检查 Ashmem:"
if [ -e /dev/ashmem ]; then
    echo -e "${GREEN}✓ Ashmem 设备存在${NC}"
else
    echo -e "${RED}✗ Ashmem 设备不存在${NC}"
fi
echo ""

# 检查 binderfs
echo "4. 检查 BinderFS:"
if mount | grep -q binderfs; then
    echo -e "${GREEN}✓ BinderFS 已挂载${NC}"
else
    echo -e "${YELLOW}⚠ BinderFS 未挂载${NC}"
fi
echo ""

# 检查 Waydroid
echo "5. 检查 Waydroid 安装:"
if command -v waydroid &> /dev/null; then
    echo -e "${GREEN}✓ Waydroid 已安装${NC}"
    waydroid --version
else
    echo -e "${RED}✗ Waydroid 未安装${NC}"
fi
echo ""

# 检查 Waydroid 容器状态
echo "6. 检查 Waydroid 容器状态:"
if systemctl is-active --quiet waydroid-container 2>/dev/null; then
    echo -e "${GREEN}✓ Waydroid 容器正在运行${NC}"
else
    echo -e "${YELLOW}⚠ Waydroid 容器未运行${NC}"
fi
echo ""

# 检查内核配置
echo "7. 检查内核配置:"
if [ -f /proc/config.gz ]; then
    for cfg in CONFIG_ANDROID CONFIG_ANDROID_BINDER_IPC CONFIG_ANDROID_BINDERFS CONFIG_ASHMEM; do
        if zcat /proc/config.gz 2>/dev/null | grep -q "^${cfg}=y"; then
            echo -e "${GREEN}✓ ${cfg}=y${NC}"
        else
            echo -e "${RED}✗ ${cfg} 未启用${NC}"
        fi
    done
else
    echo "无法找到 /proc/config.gz"
fi
echo ""

echo "=== 验证完成 ==="
```

---

## 回滚方案

### 恢复到默认内核

#### 方法 1: 临时回滚（推荐测试时使用）

```powershell
# 在 Windows PowerShell 中执行

# 1. 关闭 WSL2
wsl --shutdown

# 2. 编辑或删除 .wslconfig
# 删除 kernel 行或注释掉
notepad $env:USERPROFILE\.wslconfig

# 3. 重启 WSL2，将使用默认内核
wsl
```

#### 方法 2: 完全删除自定义内核

```powershell
# 在 Windows PowerShell 中执行

# 1. 关闭 WSL2
wsl --shutdown

# 2. 备份并删除自定义内核
Rename-Item C:\wsl2-kernel C:\wsl2-kernel-backup -Force

# 3. 删除或清空 .wslconfig
Remove-Item $env:USERPROFILE\.wslconfig -Force

# 4. 重启 WSL2
wsl
```

#### 方法 3: 使用备份恢复

```bash
# 在 WSL2 中执行

# 如果之前有备份默认内核配置
cd ~/wsl2-kernel-build/WSL2-Linux-Kernel

# 使用默认配置重新编译
cp Microsoft/config-wsl .config
make olddefconfig
make -j$(nproc)

# 安装默认内核
cp arch/x86/boot/bzImage /mnt/c/wsl2-kernel/bzImage-default
```

---

## 常见问题排查

### 问题 1: 编译失败 - 缺少依赖

**症状:**
```
/bin/sh: 1: flex: not found
/bin/sh: 1: bison: not found
```

**解决:**
```bash
sudo apt update
sudo apt install -y build-essential flex bison libssl-dev libelf-dev
```

### 问题 2: 编译失败 - 配置错误

**症状:**
```
error: Cannot generate ORC metadata for CONFIG_UNWINDER_ORC=y
```

**解决:**
```bash
# 安装 dwarves
sudo apt install dwarves

# 清理并重新配置
make clean
make olddefconfig
make -j$(nproc)
```

### 问题 3: 新内核未生效

**症状:**
`uname -r` 显示的还是旧版本

**解决:**
```powershell
# 1. 确认 .wslconfig 路径正确
# 文件应该在: C:\Users\<用户名>\.wslconfig

# 2. 确认内核路径正确
# 使用双反斜杠或正斜杠
kernel=C:\\wsl2-kernel\\bzImage-waydroid
# 或
kernel=C:/wsl2-kernel/bzImage-waydroid

# 3. 完全关闭 WSL2
wsl --shutdown

# 4. 等待 8 秒后重新启动
wsl
```

### 问题 4: Waydroid 无法启动 - binder 设备不存在

**症状:**
```
Failed to start waydroid container
binder: cannot open /dev/binder
```

**解决:**
```bash
# 1. 检查内核是否真的支持 binder
ls -la /dev/binder*

# 2. 如果没有，手动挂载 binderfs
sudo mkdir -p /dev/binderfs
sudo mount -t binder binder /dev/binderfs

# 3. 创建 binder 设备节点
sudo ln -sf /dev/binderfs/binder /dev/binder
sudo ln -sf /dev/binderfs/hwbinder /dev/hwbinder
sudo ln -sf /dev/binderfs/vndbinder /dev/vndbinder
```

### 问题 5: 磁盘空间不足

**症状:**
```
No space left on device
```

**解决:**
```bash
# 清理编译中间文件
cd ~/wsl2-kernel-build/WSL2-Linux-Kernel
make clean

# 或者删除整个编译目录
cd ~
rm -rf ~/wsl2-kernel-build

# 扩展 WSL2 磁盘空间（在 Windows PowerShell 中）
wsl --shutdown
diskpart
# 在 diskpart 中:
# select vdisk file="%LOCALAPPDATA%\Packages\CanonicalGroupLimited...\LocalState\ext4.vhdx"
# expand vdisk maximum=<新大小MB>
```

### 问题 6: 网络问题导致 git clone 失败

**症状:**
```
fatal: unable to access 'https://github.com/...': Connection timed out
```

**解决:**
```bash
# 使用镜像或代理
git clone https://ghproxy.com/https://github.com/microsoft/WSL2-Linux-Kernel.git

# 或者设置代理
git config --global http.proxy http://proxy.example.com:8080
git config --global https.proxy http://proxy.example.com:8080
```

### 问题 7: Waydroid 图形界面无法显示

**症状:**
Waydroid 容器运行但无法显示 UI

**解决:**
```bash
# 1. 确保安装了必要的图形支持
sudo apt install -y weston

# 2. 设置 DISPLAY 环境变量
export DISPLAY=:0

# 3. 在 Windows 上安装 VcXsrv 或类似 X Server
# 下载地址: https://sourceforge.net/projects/vcxsrv/

# 4. 使用以下命令启动 Waydroid
waydroid session start
waydroid show-full-ui
```

---

## 参考资源

- [微软 WSL2 内核源码](https://github.com/microsoft/WSL2-Linux-Kernel)
- [Waydroid 官方文档](https://docs.waydro.id/)
- [WSL2 内核编译官方指南](https://docs.microsoft.com/en-us/windows/wsl/kernel-release-notes)
- [Waydroid GitHub Issues](https://github.com/waydroid/waydroid/issues)

---

## 更新日志

| 日期 | 版本 | 说明 |
|------|------|------|
| 2024-XX-XX | 1.0 | 初始版本 |

---

*本文档由 AI 助手生成，如有问题请参考官方文档或提交 Issue。*
