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
  - **注意**: Build 19045 (22H2) 完全支持，满足最低版本要求
- WSL2 已安装并配置
- 至少 20GB 可用磁盘空间
- 稳定的网络连接

### 重要提示
在开始编译前，建议备份当前 WSL2 配置：
```bash
# 备份当前内核配置（如果存在）
if [ -f /proc/config.gz ]; then
    zcat /proc/config.gz > ~/wsl2-kernel-backup-$(date +%Y%m%d).config
    echo "配置已备份到: ~/wsl2-kernel-backup-$(date +%Y%m%d).config"
fi

# 记录当前内核版本
uname -r > ~/wsl2-original-kernel-version.txt
echo "原始内核版本已记录"
```

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
    python3-pip \
    ccache

# 配置 ccache 加速重复编译（可选但推荐）
ccache --max-size=5G
export PATH="/usr/lib/ccache:$PATH"
echo 'export PATH="/usr/lib/ccache:$PATH"' >> ~/.bashrc
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

# 版本差异处理说明：
# 如果找不到完全匹配的版本（如 5.15.90.1 不存在但有 5.15.90.2）：
# 1. 使用最接近的更高版本（推荐）
# 2. 或继续使用当前最新版本
# 小版本差异（如 5.15.90.x）通常不会影响 Waydroid 功能
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

# 确保配置是最新的 (使用 olddefconfig 避免交互式提示)
make olddefconfig
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

# WSL2 Waydroid 内核一键编译脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置路径（可自定义）
WIN_KERNEL_PATH="${WIN_KERNEL_PATH:-/mnt/c/wsl2-kernel}"
KERNEL_BUILD_DIR="${KERNEL_BUILD_DIR:-$HOME/wsl2-kernel-build}"

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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查是否以sudo运行
check_sudo() {
    log_step "检查权限..."
    if [ "$EUID" -ne 0 ]; then
        log_error "此脚本需要以 sudo 权限运行"
        log_error "请使用: sudo $0"
        exit 1
    fi
    log_info "权限检查通过"
}

# 检查是否在 WSL2 中运行
check_wsl2() {
    log_step "检查 WSL2 环境..."
    if ! grep -q "microsoft" /proc/version 2>/dev/null && ! grep -q "WSL" /proc/version 2>/dev/null; then
        log_error "此脚本必须在 WSL2 环境中运行"
        log_error "当前环境: $(cat /proc/version 2>/dev/null || echo 'Unknown')"
        exit 1
    fi
    log_info "WSL2 环境检测通过"
    log_info "当前内核版本: $(uname -r)"
}

# 检查磁盘空间
check_disk_space() {
    log_step "检查磁盘空间..."
    # 检查构建目录所在分区的可用空间
    local build_dir="${KERNEL_BUILD_DIR:-$HOME/wsl2-kernel-build}"
    # 确保目录存在以便 df 可以正确检查
    mkdir -p "$build_dir" 2>/dev/null || true
    local available=$(df "$build_dir" | tail -1 | awk '{print $4}')
    local required=20971520 # 20GB in KB (预计算避免溢出)
    local available_gb=$((available / 1024 / 1024))

    log_info "构建目录: $build_dir"
    log_info "可用磁盘空间: ${available_gb}GB"

    if [ "$available" -lt "$required" ]; then
        log_error "磁盘空间不足。需要至少 20GB，当前可用: ${available_gb}GB"
        log_error "请清理磁盘空间后重试"
        exit 1
    fi
    log_info "磁盘空间检查通过"
}

# 检查网络连接
check_network() {
    log_step "检查网络连接..."
    if ! ping -c 1 github.com &>/dev/null; then
        log_warn "无法连接到 GitHub，请检查网络连接"
        log_warn "如果在中国大陆，可能需要配置代理"
        read -p "是否继续? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_info "网络连接正常"
    fi
}

# 安装依赖
install_dependencies() {
    log_step "安装编译依赖..."
    
    local deps=(
        "build-essential"
        "flex"
        "bison"
        "libssl-dev"
        "libelf-dev"
        "libncurses-dev"
        "autoconf"
        "libudev-dev"
        "libtool"
        "dwarves"
        "bc"
        "git"
        "wget"
        "python3"
        "python3-pip"
        "ccache"
    )
    
    log_info "更新软件包列表..."
    apt update
    
    log_info "安装依赖包..."
    apt install -y "${deps[@]}"
    
    # 配置 ccache 加速重复编译
    log_info "配置 ccache..."
    ccache --max-size=5G
    export PATH="/usr/lib/ccache:$PATH"
    
    log_info "依赖安装完成"
}

# 下载内核源码
download_kernel() {
    log_step "下载 WSL2 内核源码..."
    
    mkdir -p "${KERNEL_BUILD_DIR}"
    cd "${KERNEL_BUILD_DIR}"
    
    if [ -d "WSL2-Linux-Kernel" ]; then
        log_warn "内核源码目录已存在"
        read -p "是否重新下载? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "删除旧目录..."
            rm -rf WSL2-Linux-Kernel
            git clone https://github.com/microsoft/WSL2-Linux-Kernel.git
        else
            log_info "更新现有仓库..."
            cd WSL2-Linux-Kernel
            git fetch --tags
        fi
    else
        log_info "克隆内核仓库..."
        git clone https://github.com/microsoft/WSL2-Linux-Kernel.git
    fi
    
    cd WSL2-Linux-Kernel
    
    # 获取匹配的版本
    local kernel_version=$(uname -r | cut -d'-' -f1)
    local tag="linux-msft-wsl-${kernel_version}"
    
    log_info "查找匹配的内核版本标签..."
    
    # 获取所有标签
    git fetch --tags --force
    
    if git tag | grep -q "^${tag}$"; then
        log_info "找到精确匹配的版本: ${tag}"
        git checkout "${tag}"
    else
        log_warn "未找到精确匹配的版本: ${tag}"
        log_info "可用的版本标签:"
        git tag | grep "linux-msft-wsl-" | sort -V | tail -5
        
        local latest_tag=$(git tag | grep "linux-msft-wsl-" | sort -V | tail -1)
        log_info "使用最新版本: ${latest_tag}"
        git checkout "${latest_tag}"
    fi
    
    log_info "内核源码准备完成"
}

# 配置内核
configure_kernel() {
    log_step "配置内核..."
    
    # 使用当前配置
    if [ -f /proc/config.gz ]; then
        log_info "使用当前运行的内核配置作为基础"
        zcat /proc/config.gz > .config
    else
        log_info "使用仓库默认配置"
        if [ -f Microsoft/config-wsl ]; then
            cp Microsoft/config-wsl .config
        else
            log_error "找不到默认配置文件"
            exit 1
        fi
    fi
    
    # 启用 Waydroid 所需模块
    log_info "启用 Waydroid 内核模块..."
    
    # 定义需要启用的配置（布尔值类型）
    declare -a enable_configs=(
        "CONFIG_ANDROID"
        "CONFIG_ANDROID_BINDER_IPC"
        "CONFIG_ANDROID_BINDERFS"
        "CONFIG_ASHMEM"
        "CONFIG_MEMCG"
        "CONFIG_CGROUP_DEVICE"
    )

    for cfg in "${enable_configs[@]}"; do
        # 删除旧配置
        sed -i "/^${cfg}=/d" .config
        # 添加新配置
        echo "${cfg}=y" >> .config
    done

    # 添加 binder 设备配置（字符串类型）
    sed -i '/^CONFIG_ANDROID_BINDER_DEVICES=/d' .config
    echo 'CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"' >> .config
    
    # 更新配置
    log_info "更新内核配置..."
    make olddefconfig 2>&1 | tail -20
    
    log_info "内核配置完成"
    
    # 显示关键配置
    log_info "验证关键配置:"
    echo "----------------------------------------"
    for cfg in "${enable_configs[@]}"; do
        local value=$(grep "^${cfg}=" .config 2>/dev/null || echo "${cfg}=NOT_SET")
        if echo "$value" | grep -q "=y"; then
            echo -e "${GREEN}✓${NC} $value"
        else
            echo -e "${RED}✗${NC} $value"
        fi
    done
    echo "----------------------------------------"
}

# 编译内核
compile_kernel() {
    log_step "编译内核..."
    log_warn "这可能需要 30-60 分钟，请耐心等待..."
    log_warn "期间请勿关闭终端"
    
    local start_time=$(date +%s)
    local cpu_count=$(nproc)
    local build_log=$(mktemp /tmp/kernel-build.XXXXXX.log)
    
    log_info "使用 ${cpu_count} 个 CPU 核心进行编译"
    log_info "编译日志: ${build_log}"
    
    # 编译
    log_info "开始编译，显示关键进度信息..."
    make -j"${cpu_count}" 2>&1 | tee "${build_log}"
    local make_exit_code=${PIPESTATUS[0]}

    if [ $make_exit_code -eq 0 ]; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))

        log_info "内核编译成功！"
        log_info "编译耗时: ${minutes} 分 ${seconds} 秒"
        # 保留成功的编译日志
        cp "${build_log}" "${WIN_KERNEL_PATH}/build.log" 2>/dev/null || true
        rm -f "${build_log}"
    else
        log_error "内核编译失败 (退出码: $make_exit_code)"
        log_error "请查看 ${build_log} 了解详细错误信息"
        exit 1
    fi
    
    # 验证内核镜像
    if [ ! -f "arch/x86/boot/bzImage" ]; then
        log_error "内核镜像未找到"
        exit 1
    fi
    
    local kernel_size=$(du -h arch/x86/boot/bzImage | cut -f1)
    log_info "内核镜像大小: ${kernel_size}"
}

# 安装内核
install_kernel() {
    log_step "安装内核..."
    
    # 创建 Windows 目录
    if [ ! -d "${WIN_KERNEL_PATH}" ]; then
        log_info "创建目录: ${WIN_KERNEL_PATH}"
        mkdir -p "${WIN_KERNEL_PATH}"
    fi
    
    # 备份旧内核
    if [ -f "${WIN_KERNEL_PATH}/bzImage-waydroid" ]; then
        log_info "备份旧内核..."
        cp "${WIN_KERNEL_PATH}/bzImage-waydroid" "${WIN_KERNEL_PATH}/bzImage-waydroid.backup.$(date +%Y%m%d%H%M%S)"
    fi
    
    # 复制内核
    log_info "复制内核到 Windows..."
    cp arch/x86/boot/bzImage "${WIN_KERNEL_PATH}/bzImage-waydroid"
    cp .config "${WIN_KERNEL_PATH}/config-waydroid"
    
    # 记录编译信息
    cat > "${WIN_KERNEL_PATH}/build-info.txt" << EOF
编译时间: $(date)
内核版本: $(make kernelrelease 2>/dev/null || echo 'Unknown')
Git 提交: $(git rev-parse --short HEAD 2>/dev/null || echo 'Unknown')
编译主机: $(uname -a)
EOF
    
    log_info "内核已安装到: ${WIN_KERNEL_PATH}/bzImage-waydroid"
}

# 生成 WSL 配置
generate_wsl_config() {
    log_step "生成 WSL 配置..."
    
    local config_file="${WIN_KERNEL_PATH}/.wslconfig-template"
    
    # 获取系统内存信息
    local total_mem=$(free -g | awk '/^Mem:/{print $2}')
    local mem_limit=$((total_mem / 2))
    if [ "$mem_limit" -lt 4 ]; then
        mem_limit=4
    fi
    
    # 获取 CPU 核心数
    local cpu_count=$(nproc)
    local cpu_limit=$((cpu_count / 2))
    if [ "$cpu_limit" -lt 2 ]; then
        cpu_limit=2
    fi
    
    # 获取Windows路径格式 (将 /mnt/x/path 转换为 X:\\path 格式)
    # WSL2 .wslconfig 文件需要使用双反斜杠作为路径分隔符
    # 支持任意盘符 (c, d, e等)
    local win_path=$(echo "${WIN_KERNEL_PATH}" | sed 's|/mnt/\([a-zA-Z]\)/|\1:\\\\|' | sed 's|/|\\\\|g')
    
    cat > "$config_file" << EOF
# WSL2 配置文件
# 将此内容复制到 %USERPROFILE%\.wslconfig (Windows 用户目录下)

[wsl2]
# 自定义内核路径
kernel=${win_path}\\\bzImage-waydroid

# 内存限制 (根据你的系统调整)
memory=${mem_limit}GB

# CPU 核心数 (根据你的系统调整)
processors=${cpu_limit}

# 交换文件大小
swap=2GB

# 本地端口转发
localhostForwarding=true

# 网络模式 (可选)
# networkingMode=mirrored
EOF
    
    log_info "WSL 配置模板已保存"
    log_info "位置: ${WIN_KERNEL_PATH}/.wslconfig-template"
    
    # 显示配置内容
    echo ""
    echo "===== WSL 配置内容 ====="
    cat "$config_file"
    echo "========================"
    echo ""
}

# 显示完成信息
show_completion_info() {
    log_step "编译完成！"
    
    echo ""
    echo "========================================"
    echo "  WSL2 Waydroid 内核编译成功！"
    echo "========================================"
    echo ""
    echo "下一步操作:"
    echo ""
    echo "1. 在 Windows PowerShell 中执行:"
    echo "   notepad \$env:USERPROFILE\\.wslconfig"
    echo ""
    echo "2. 添加以下内容:"
    echo "   [wsl2]"
    echo "   kernel=C:\\\\wsl2-kernel\\\\bzImage-waydroid"
    echo "   memory=8GB"
    echo "   processors=4"
    echo "   swap=2GB"
    echo "   localhostForwarding=true"
    echo ""
    echo "3. 保存文件后，在 PowerShell 中执行:"
    echo "   wsl --shutdown"
    echo ""
    echo "4. 等待 8 秒后重新启动 WSL2:"
    echo "   wsl"
    echo ""
    echo "5. 验证新内核:"
    echo "   uname -r"
    echo ""
    echo "6. 安装 Waydroid:"
    echo "   sudo apt install waydroid"
    echo "   sudo waydroid init"
    echo ""
    echo "========================================"
    echo ""
    
    # 创建验证脚本
    local verify_script="${WIN_KERNEL_PATH}/verify-waydroid.sh"
    cat > "$verify_script" << 'VERIFY_SCRIPT'
#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== WSL2 Waydroid 验证脚本 ==="
echo ""

# 检查内核
echo "1. 检查内核版本:"
echo "   $(uname -r)"
echo ""

# 检查 binder 设备
echo "2. 检查 Binder 设备:"
if ls /dev/binder* 2>/dev/null | head -3; then
    echo -e "   ${GREEN}✓ Binder 设备存在${NC}"
else
    echo -e "   ${RED}✗ Binder 设备不存在${NC}"
fi
echo ""

# 检查 ashmem
echo "3. 检查 Ashmem:"
if [ -e /dev/ashmem ]; then
    echo -e "   ${GREEN}✓ Ashmem 设备存在${NC}"
else
    echo -e "   ${RED}✗ Ashmem 设备不存在${NC}"
fi
echo ""

# 检查 binderfs
echo "4. 检查 BinderFS:"
if mount | grep -q binderfs; then
    echo -e "   ${GREEN}✓ BinderFS 已挂载${NC}"
else
    echo -e "   ${YELLOW}⚠ BinderFS 未挂载${NC}"
fi
echo ""

# 检查 Waydroid
echo "5. 检查 Waydroid 安装:"
if command -v waydroid &>/dev/null; then
    echo -e "   ${GREEN}✓ Waydroid 已安装${NC}"
    echo "   版本: $(waydroid --version 2>/dev/null || echo 'Unknown')"
else
    echo -e "   ${RED}✗ Waydroid 未安装${NC}"
fi
echo ""

# 检查内核配置
echo "6. 检查内核配置:"
if [ -f /proc/config.gz ]; then
    for cfg in CONFIG_ANDROID CONFIG_ANDROID_BINDER_IPC CONFIG_ANDROID_BINDERFS CONFIG_ASHMEM CONFIG_MEMCG CONFIG_CGROUP_DEVICE; do
        if zcat /proc/config.gz 2>/dev/null | grep -q "^${cfg}=y"; then
            echo -e "   ${GREEN}✓${NC} ${cfg}=y"
        else
            echo -e "   ${RED}✗${NC} ${cfg} 未启用"
        fi
    done
fi
echo ""

echo "=== 验证完成 ==="
VERIFY_SCRIPT
    
    chmod +x "$verify_script"
    log_info "验证脚本已保存到: ${WIN_KERNEL_PATH}/verify-waydroid.sh"
}

# 主函数
main() {
    echo ""
    echo "========================================"
    echo "  WSL2 Waydroid 内核编译脚本"
    echo "========================================"
    echo ""
    log_info "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # 检查步骤
    check_sudo
    check_wsl2
    check_disk_space
    check_network
    
    # 安装依赖
    install_dependencies
    
    # 下载和编译
    download_kernel
    configure_kernel
    compile_kernel
    install_kernel
    generate_wsl_config
    
    # 完成
    show_completion_info
    
    log_info "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

# 错误处理
trap 'log_error "脚本执行出错，行号: $LINENO，命令: $BASH_COMMAND"' ERR

# 信号处理
trap 'log_warn "脚本被中断"; exit 130' INT TERM

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

#### Waydroid 初始化选项说明

| 初始化命令 | 说明 | 适用场景 |
|-----------|------|---------|
| `sudo waydroid init` | 标准 LineageOS 镜像，无 Google 服务 | 不需要 Google 服务，追求纯净体验 |
| `sudo waydroid init -g` | 包含 Google Play 服务和应用商店 | 需要 Google 账号登录和 Play 商店 |
| `sudo waydroid init -f` | 强制重新初始化（覆盖现有数据） | 需要重置 Waydroid 环境 |

**注意**: 带 Google Play 的镜像较大（约 1GB+），初始化时间更长。

```bash
# 安装 Waydroid
sudo apt install -y waydroid

# 初始化 Waydroid（选择以下一种）
# 选项 1: 标准镜像（推荐初次尝试）
sudo waydroid init

# 选项 2: 带 Google Play 服务
# sudo waydroid init -g

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

# WSL2 Waydroid 验证脚本
# 用于验证内核编译是否成功以及 Waydroid 是否可以正常运行

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置路径（可自定义）
WIN_KERNEL_PATH="${WIN_KERNEL_PATH:-/mnt/c/wsl2-kernel}"

# 计数器 (初始化确保 set -e 不会导致退出)
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# 使用算术扩展进行递增，避免 set -e 在结果为0时退出
increment_pass() { PASS_COUNT=$((PASS_COUNT + 1)); }
increment_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); }
increment_warn() { WARN_COUNT=$((WARN_COUNT + 1)); }

# 日志函数
log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    increment_pass
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    increment_fail
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    increment_warn
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# 检查内核版本
check_kernel() {
    echo ""
    log_info "========== 1. 内核版本检查 =========="

    local kernel_version=$(uname -r)
    echo "当前内核版本: $kernel_version"

    if echo "$kernel_version" | grep -q "microsoft"; then
        log_pass "WSL2 内核运行正常"
    else
        log_fail "当前不是 WSL2 内核"
    fi

    # 检查内核编译时间
    local version_info=$(cat /proc/version)
    echo "内核详细信息: $version_info"
}

# 检查内核配置
check_kernel_config() {
    echo ""
    log_info "========== 2. 内核配置检查 =========="

    local config_source=""
    if [ -f /proc/config.gz ]; then
        config_source="/proc/config.gz"
    elif [ -f "/boot/config-$(uname -r)" ]; then
        config_source="/boot/config-$(uname -r)"
    fi

    if [ -z "$config_source" ]; then
        log_warn "找不到内核配置文件"
        return
    fi

    log_info "使用配置源: $config_source"

    # 定义需要检查的配置
    declare -a required_configs=(
        "CONFIG_ANDROID"
        "CONFIG_ANDROID_BINDER_IPC"
        "CONFIG_ANDROID_BINDERFS"
        "CONFIG_ASHMEM"
    )

    for cfg in "${required_configs[@]}"; do
        local result
        if [ "$config_source" = "/proc/config.gz" ]; then
            result=$(zcat /proc/config.gz 2>/dev/null | grep "^${cfg}=" || echo "")
        else
            result=$(grep "^${cfg}=" "$config_source" || echo "")
        fi

        if echo "$result" | grep -q "=y"; then
            log_pass "$result"
        elif echo "$result" | grep -q "=m"; then
            log_warn "$result (模块形式，可能需要手动加载)"
        else
            log_fail "$cfg 未启用"
        fi
    done
}

# 检查 binder 设备
check_binder() {
    echo ""
    log_info "========== 3. Binder 设备检查 =========="
    
    # 检查 binder 设备节点
    local binder_devices=("/dev/binder" "/dev/hwbinder" "/dev/vndbinder")
    local found_count=0
    
    for device in "${binder_devices[@]}"; do
        if [ -e "$device" ]; then
            local perms=$(ls -la "$device" 2>/dev/null | awk '{print $1, $3, $4}')
            log_pass "$device 存在 ($perms)"
            found_count=$((found_count + 1))
        else
            log_fail "$device 不存在"
        fi
    done
    
    # 检查 binderfs
    echo ""
    log_info "检查 BinderFS 挂载..."
    if mount | grep -q "binderfs"; then
        log_pass "BinderFS 已挂载"
        mount | grep "binderfs"
        
        # 检查 binderfs 中的设备
        if [ -d "/dev/binderfs" ]; then
            echo "BinderFS 设备列表:"
            ls -la /dev/binderfs/ 2>/dev/null | head -10
        fi
    else
        log_warn "BinderFS 未挂载"
        echo "提示: 可以尝试手动挂载:"
        echo "  sudo mkdir -p /dev/binderfs"
        echo "  sudo mount -t binder binder /dev/binderfs"
    fi
}

# 检查 ashmem
check_ashmem() {
    echo ""
    log_info "========== 4. Ashmem 检查 =========="
    
    if [ -e "/dev/ashmem" ]; then
        local perms=$(ls -la /dev/ashmem 2>/dev/null | awk '{print $1, $3, $4}')
        log_pass "/dev/ashmem 存在 ($perms)"
    else
        log_fail "/dev/ashmem 不存在"
    fi
    
    # 检查 ashmem 模块
    if lsmod 2>/dev/null | grep -q "ashmem"; then
        log_pass "ashmem 模块已加载"
        lsmod | grep "ashmem"
    else
        log_warn "ashmem 模块未加载 (可能已静态编译到内核)"
    fi
}

# 检查 Waydroid 安装
check_waydroid_install() {
    echo ""
    log_info "========== 5. Waydroid 安装检查 =========="
    
    if command -v waydroid &>/dev/null; then
        local version=$(waydroid --version 2>/dev/null || echo "Unknown")
        log_pass "Waydroid 已安装 (版本: $version)"
        
        # 检查 Waydroid 配置
        if [ -d "/var/lib/waydroid" ]; then
            log_pass "Waydroid 配置目录存在"
            ls -la /var/lib/waydroid/ 2>/dev/null | head -5
        else
            log_warn "Waydroid 配置目录不存在，可能需要初始化"
            echo "提示: 运行 'sudo waydroid init' 进行初始化"
        fi
        
        # 检查 Waydroid 镜像
        if [ -f "/usr/share/waydroid-extra/images/system.img" ] || \
           [ -f "/var/lib/waydroid/images/system.img" ]; then
            log_pass "Waydroid 系统镜像存在"
        else
            log_warn "Waydroid 系统镜像不存在，需要初始化"
        fi
        
    else
        log_fail "Waydroid 未安装"
        echo "提示: 安装命令:"
        echo "  sudo apt install waydroid"
        echo "  sudo waydroid init"
    fi
}

# 检查 Waydroid 容器状态
check_waydroid_container() {
    echo ""
    log_info "========== 6. Waydroid 容器状态 =========="
    
    if ! command -v waydroid &>/dev/null; then
        log_warn "Waydroid 未安装，跳过容器检查"
        return
    fi
    
    # 检查容器服务
    if systemctl is-active --quiet waydroid-container 2>/dev/null; then
        log_pass "Waydroid 容器服务正在运行"
        
        # 获取容器状态
        echo ""
        log_info "Waydroid 状态:"
        waydroid status 2>/dev/null || log_warn "无法获取 Waydroid 状态"
        
    else
        log_warn "Waydroid 容器服务未运行"
        echo "提示: 启动命令:"
        echo "  sudo systemctl start waydroid-container"
        echo "  或"
        echo "  sudo waydroid container start"
    fi
}

# 检查系统资源
check_system_resources() {
    echo ""
    log_info "========== 7. 系统资源检查 =========="
    
    # 检查内存
    local mem_info=$(free -h | grep "^Mem:")
    echo "内存信息: $mem_info"
    
    local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$mem_gb" -ge 4 ]; then
        log_pass "内存充足 (${mem_gb}GB)"
    else
        log_warn "内存可能不足 (${mem_gb}GB)，建议至少 4GB"
    fi
    
    # 检查磁盘空间
    echo ""
    local disk_info=$(df -h /var/lib 2>/dev/null | tail -1 || df -h / | tail -1)
    echo "磁盘信息: $disk_info"
    
    local disk_gb=$(df -BG /var/lib 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G' || \
                    df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')
    if [ "$disk_gb" -ge 10 ]; then
        log_pass "磁盘空间充足 (${disk_gb}GB)"
    else
        log_warn "磁盘空间可能不足 (${disk_gb}GB)，建议至少 10GB"
    fi
}

# 检查 cgroup 支持
check_cgroup() {
    echo ""
    log_info "========== 8. Cgroup 支持检查 =========="
    
    # 检查 cgroup 挂载
    if mount | grep -q "cgroup"; then
        log_pass "Cgroup 已挂载"
        
        # 检查 cgroup 版本
        if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
            log_pass "Cgroup v2 可用"
        else
            log_info "Cgroup v1 可用"
        fi
        
        # 检查必要的控制器
        local controllers=$(cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null || \
                           ls /sys/fs/cgroup/ 2>/dev/null | head -10)
        echo "可用控制器: $controllers"
    else
        log_warn "Cgroup 未挂载"
    fi
}

# 提供修复建议
provide_fixes() {
    echo ""
    log_info "========== 修复建议 =========="
    
    if [ $FAIL_COUNT -eq 0 ] && [ $WARN_COUNT -eq 0 ]; then
        log_pass "所有检查通过！Waydroid 应该可以正常运行。"
        echo ""
        echo "启动 Waydroid 的命令:"
        echo "  1. 启动容器: sudo systemctl start waydroid-container"
        echo "  2. 启动会话: waydroid session start"
        echo "  3. 显示 UI:  waydroid show-full-ui"
        return
    fi
    
    echo ""
    echo "根据检查结果，以下是可能的修复步骤:"
    echo ""
    
    if [ $FAIL_COUNT -gt 0 ]; then
        echo "${RED}必须修复的问题:${NC}"
        
        # 检查是否需要重新编译内核
        if ! zcat /proc/config.gz 2>/dev/null | grep -q "^CONFIG_ANDROID=y"; then
            echo ""
            echo "1. 内核缺少 Android 支持，需要重新编译内核:"
            echo "   - 运行 build-wsl2-waydroid-kernel.sh 脚本重新编译"
            echo "   - 确保 CONFIG_ANDROID=y 等选项已启用"
        fi
        
        # 检查 binder 设备
        if [ ! -e "/dev/binder" ]; then
            echo ""
            echo "2. Binder 设备不存在，尝试手动创建:"
            echo "   sudo mkdir -p /dev/binderfs"
            echo "   sudo mount -t binder binder /dev/binderfs"
            echo "   sudo ln -sf /dev/binderfs/binder /dev/binder"
            echo "   sudo ln -sf /dev/binderfs/hwbinder /dev/hwbinder"
            echo "   sudo ln -sf /dev/binderfs/vndbinder /dev/vndbinder"
        fi
    fi
    
    if [ $WARN_COUNT -gt 0 ]; then
        echo ""
        echo "${YELLOW}建议修复的警告:${NC}"
        
        # 检查 Waydroid 安装
        if ! command -v waydroid &>/dev/null; then
            echo ""
            echo "- 安装 Waydroid:"
            echo "  sudo apt update"
            echo "  sudo apt install waydroid -y"
            echo "  sudo waydroid init"
        fi
        
        # 检查容器服务
        if command -v waydroid &>/dev/null && ! systemctl is-active --quiet waydroid-container 2>/dev/null; then
            echo ""
            echo "- 启动 Waydroid 容器:"
            echo "  sudo systemctl enable waydroid-container"
            echo "  sudo systemctl start waydroid-container"
        fi
    fi
}

# 主函数
main() {
    echo ""
    echo "========================================"
    echo "  WSL2 Waydroid 验证脚本"
    echo "========================================"
    echo ""
    log_info "开始验证: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # 运行所有检查
    check_kernel
    check_kernel_config
    check_binder
    check_ashmem
    check_waydroid_install
    check_waydroid_container
    check_system_resources
    check_cgroup
    
    # 显示统计
    echo ""
    echo "========================================"
    echo "  验证结果统计"
    echo "========================================"
    echo -e "${GREEN}通过: $PASS_COUNT${NC}"
    echo -e "${YELLOW}警告: $WARN_COUNT${NC}"
    echo -e "${RED}失败: $FAIL_COUNT${NC}"
    echo "========================================"
    
    # 提供修复建议
    provide_fixes
    
    echo ""
    log_info "验证完成: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # 返回状态码
    if [ $FAIL_COUNT -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# 运行主函数
main "$@"
```

---

## 回滚方案

### 一键回滚脚本: `rollback-wsl2-kernel.sh`

```bash
#!/bin/bash

# WSL2 内核回滚脚本
# 用于恢复到默认内核或备份的内核

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置路径（可自定义）
WIN_KERNEL_PATH="${WIN_KERNEL_PATH:-/mnt/c/wsl2-kernel}"

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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 显示菜单
show_menu() {
    echo ""
    echo "========================================"
    echo "  WSL2 内核回滚工具"
    echo "========================================"
    echo ""
    echo "请选择操作:"
    echo ""
    echo "  1) 临时回滚到默认内核 (保留自定义内核)"
    echo "  2) 完全删除自定义内核，恢复默认"
    echo "  3) 从备份恢复自定义内核"
    echo "  4) 查看当前内核信息"
    echo "  5) 查看可用的内核备份"
    echo "  6) 退出"
    echo ""
    echo "========================================"
}

# 检查 WSL2 环境
check_wsl2() {
    if ! grep -q "microsoft" /proc/version 2>/dev/null && ! grep -q "WSL" /proc/version 2>/dev/null; then
        log_error "此脚本必须在 WSL2 环境中运行"
        exit 1
    fi
}

# 获取 Windows 用户目录（转换为 WSL 路径格式）
get_windows_userprofile() {
    local win_userprofile="$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')"
    # 转换为 WSL 路径格式: C:\Users\Username -> /mnt/c/Users/Username
    # 使用 tr 转换反斜杠，使用 sed 转换盘符 (不区分大小写)
    local wsl_path="$(echo "$win_userprofile" | tr '\\' '/' | sed 's/^[Cc]:/\/mnt\/c/' | sed 's/^[Dd]:/\/mnt\/d/')"
    echo "$wsl_path"
}

# 关闭 WSL2
shutdown_wsl() {
    log_step "关闭 WSL2..."
    
    log_warn "即将关闭 WSL2，所有 WSL 会话将被终止"
    read -p "是否继续? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "操作已取消"
        return 1
    fi
    
    # 在 Windows 中执行关闭命令
    cmd.exe /c "wsl --shutdown" 2>/dev/null || {
        log_error "无法关闭 WSL2，请在 Windows PowerShell 中手动执行: wsl --shutdown"
        return 1
    }
    
    log_info "WSL2 已关闭"
    log_warn "请等待 8 秒确保完全关闭..."
    sleep 8
    
    return 0
}

# 选项 1: 临时回滚到默认内核
temp_rollback() {
    log_step "临时回滚到默认内核"

    local wsl_userprofile=$(get_windows_userprofile)
    local wslconfig_path="${wsl_userprofile}/.wslconfig"

    log_info "WSL 配置文件路径: $wslconfig_path"

    # 检查配置文件是否存在
    if [ ! -f "$wslconfig_path" ] 2>/dev/null; then
        log_warn "WSL 配置文件不存在"
        log_info "当前已经在使用默认内核"
        return
    fi

    # 备份当前配置
    local backup_path="${wslconfig_path}.backup.$(date +%Y%m%d%H%M%S)"
    log_info "备份当前配置到: $backup_path"
    cp "$wslconfig_path" "$backup_path" 2>/dev/null || true

    # 注释掉 kernel 行
    log_info "修改 WSL 配置..."
    sed -i 's/^kernel=/# kernel=/' "$wslconfig_path" 2>/dev/null || {
        log_error "无法修改配置文件"
        log_info "请手动编辑文件: $wslconfig_path"
        log_info "将 kernel= 行注释掉或删除"
        return 1
    }
    
    log_info "配置已修改"
    
    # 关闭 WSL2
    if shutdown_wsl; then
        log_info "回滚完成！"
        log_info "请重新启动 WSL2: wsl"
        log_info "新会话将使用默认内核"
    fi
}

# 选项 2: 完全删除自定义内核
full_rollback() {
    log_step "完全删除自定义内核"

    local wsl_userprofile=$(get_windows_userprofile)
    local wslconfig_path="${wsl_userprofile}/.wslconfig"
    local kernel_dir="${WIN_KERNEL_PATH}"

    log_warn "此操作将:"
    log_warn "  - 删除自定义内核文件"
    log_warn "  - 删除 WSL 配置文件"
    log_warn "  - 恢复到微软默认内核"
    echo ""
    read -p "是否继续? (y/N): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "操作已取消"
        return
    fi

    # 备份并删除内核目录
    if [ -d "$kernel_dir" ]; then
        local backup_dir="/mnt/c/wsl2-kernel-backup-$(date +%Y%m%d%H%M%S)"
        log_info "备份内核目录到: $backup_dir"
        mv "$kernel_dir" "$backup_dir"
        log_info "内核目录已备份并删除"
    fi

    # 删除或清空 WSL 配置
    if [ -f "$wslconfig_path" ] 2>/dev/null; then
        local config_backup="${wslconfig_path}.backup.$(date +%Y%m%d%H%M%S)"
        log_info "备份 WSL 配置到: $config_backup"
        cp "$wslconfig_path" "$config_backup" 2>/dev/null || true

        log_info "删除 WSL 配置文件..."
        rm -f "$wslconfig_path"
        log_info "WSL 配置已删除"
    fi
    
    # 关闭 WSL2
    if shutdown_wsl; then
        log_info "回滚完成！"
        log_info "请重新启动 WSL2: wsl"
        log_info "系统将使用微软默认内核"
    fi
}

# 选项 3: 从备份恢复
restore_from_backup() {
    log_step "从备份恢复内核"
    
    local kernel_dir="${WIN_KERNEL_PATH}"
    local backup_dir="${WIN_KERNEL_PATH}-backup"
    
    # 查找备份
    echo ""
    log_info "查找可用的备份..."
    
    local backups=()
    
    # 查找带时间戳的备份
    for dir in "${WIN_KERNEL_PATH}"-backup-*; do
        if [ -d "$dir" ]; then
            backups+=("$dir")
        fi
    done
    
    # 查找旧内核备份
    if [ -d "$backup_dir" ]; then
        backups+=("$backup_dir")
    fi
    
    if [ ${#backups[@]} -eq 0 ]; then
        log_error "没有找到可用的备份"
        return 1
    fi
    
    echo ""
    echo "可用的备份:"
    echo ""
    
    local i=1
    for backup in "${backups[@]}"; do
        local name=$(basename "$backup")
        local size=$(du -sh "$backup" 2>/dev/null | cut -f1)
        local date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1)
        echo "  $i) $name (大小: $size, 日期: $date)"
        ((i++))
    done
    
    echo ""
    read -p "选择要恢复的备份 (1-$((i-1)), 或按 Enter 取消): " choice
    
    if [ -z "$choice" ]; then
        log_info "操作已取消"
        return
    fi
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -ge "$i" ]; then
        log_error "无效的选择"
        return 1
    fi
    
    local selected_backup="${backups[$((choice-1))]}"
    log_info "选择的备份: $(basename "$selected_backup")"
    
    # 备份当前内核
    if [ -d "$kernel_dir" ]; then
        local current_backup="/mnt/c/wsl2-kernel-current-$(date +%Y%m%d%H%M%S)"
        log_info "备份当前内核到: $current_backup"
        mv "$kernel_dir" "$current_backup"
    fi
    
    # 恢复备份
    log_info "恢复备份..."
    cp -r "$selected_backup" "$kernel_dir"
    
    log_info "内核已恢复"
    
    # 确保 WSL 配置正确
    local wsl_userprofile=$(get_windows_userprofile)
    local wslconfig_path="${wsl_userprofile}/.wslconfig"
    # WSL2 .wslconfig 文件需要使用双反斜杠作为路径分隔符
    # 支持任意盘符 (c, d, e等)
    local win_path=$(echo "${WIN_KERNEL_PATH}" | sed 's|/mnt/\([a-zA-Z]\)/|\1:\\\\|' | sed 's|/|\\\\|g')

    if [ ! -f "$wslconfig_path" ] 2>/dev/null; then
        log_info "创建 WSL 配置文件..."
        cat > "$wslconfig_path" << EOF
[wsl2]
kernel=${win_path}\\\bzImage-waydroid
memory=8GB
processors=4
swap=2GB
localhostForwarding=true
EOF
    fi
    
    # 关闭 WSL2
    if shutdown_wsl; then
        log_info "恢复完成！"
        log_info "请重新启动 WSL2: wsl"
    fi
}

# 选项 4: 查看当前内核信息
show_kernel_info() {
    log_step "当前内核信息"
    
    echo ""
    echo "========================================"
    echo "内核版本:"
    echo "  $(uname -r)"
    echo ""
    echo "内核详细信息:"
    cat /proc/version
    echo ""
    echo "编译时间:"
    uname -v
    echo ""
    echo "========================================"
    
    # 检查是否为自定义内核
    local kernel_path=$(cat /proc/cmdline | grep -o "BOOT_IMAGE=[^ ]*" | cut -d= -f2 2>/dev/null || echo "Unknown")
    echo "启动镜像: $kernel_path"
    
    # 检查 WSL 配置
    local wsl_userprofile=$(get_windows_userprofile)
    local wslconfig_path="${wsl_userprofile}/.wslconfig"

    echo ""
    echo "WSL 配置文件:"
    if [ -f "$wslconfig_path" ] 2>/dev/null; then
        echo "  路径: $wslconfig_path"
        echo "  内容:"
        cat "$wslconfig_path" | sed 's/^/    /'
    else
        echo "  未找到配置文件 (使用默认设置)"
    fi
    
    echo ""
    echo "自定义内核文件:"
    if [ -f "${WIN_KERNEL_PATH}/bzImage-waydroid" ]; then
        local kernel_size=$(du -h "${WIN_KERNEL_PATH}/bzImage-waydroid" | cut -f1)
        local kernel_date=$(stat -c %y "${WIN_KERNEL_PATH}/bzImage-waydroid" | cut -d' ' -f1)
        echo "  路径: ${WIN_KERNEL_PATH}/bzImage-waydroid"
        echo "  大小: $kernel_size"
        echo "  日期: $kernel_date"
    else
        echo "  未找到自定义内核文件"
    fi
    
    echo "========================================"
}

# 选项 5: 查看可用的备份
show_backups() {
    log_step "可用的内核备份"
    
    echo ""
    echo "========================================"
    
    local found=0
    
    # 查找带时间戳的备份
    echo "自定义内核备份:"
    for dir in "${WIN_KERNEL_PATH}"-backup-*; do
        if [ -d "$dir" ]; then
            local name=$(basename "$dir")
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            local date=$(stat -c %y "$dir" 2>/dev/null | cut -d' ' -f1)
            echo "  - $name"
            echo "    大小: $size"
            echo "    日期: $date"
            echo ""
            found=1
        fi
    done
    
    if [ $found -eq 0 ]; then
        echo "  未找到自定义内核备份"
    fi
    
    echo "----------------------------------------"
    
    # 查找配置备份 (在用户目录下查找)
    echo "WSL 配置备份:"
    local wsl_userprofile=$(get_windows_userprofile)
    # 直接在当前用户目录下查找，而不是父目录
    local config_backups=$(find "$wsl_userprofile" -maxdepth 1 -name ".wslconfig.backup.*" 2>/dev/null || true)

    if [ -n "$config_backups" ]; then
        echo "$config_backups" | while read file; do
            local name=$(basename "$file")
            local date=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1)
            echo "  - $name (日期: $date)"
        done
    else
        echo "  未找到配置备份"
    fi
    
    echo "========================================"
}

# 主函数
main() {
    check_wsl2
    
    while true; do
        show_menu
        read -p "请输入选项 (1-6): " choice
        
        case $choice in
            1)
                temp_rollback
                ;;
            2)
                full_rollback
                ;;
            3)
                restore_from_backup
                ;;
            4)
                show_kernel_info
                ;;
            5)
                show_backups
                ;;
            6)
                log_info "退出脚本"
                exit 0
                ;;
            *)
                log_error "无效的选项，请重新选择"
                ;;
        esac
        
        echo ""
        read -p "按 Enter 键继续..."
    done
}

# 错误处理
trap 'log_error "脚本执行出错"' ERR

# 运行主函数
main "$@"
```

### 手动回滚方法

如果不想使用脚本，也可以手动执行以下步骤：

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

#### 步骤 1: 在 Windows 上安装 VcXsrv X Server

1. 下载 VcXsrv: https://sourceforge.net/projects/vcxsrv/
2. 安装并运行 XLaunch，按以下配置：
   - **Display settings**: Multiple windows
   - **Display number**: 0
   - **Client startup**: Start no client
   - **Extra settings**: 
     - ☑ Clipboard
     - ☑ Primary Selection
     - ☑ Native opengl
     - ☑ Disable access control (重要！允许 WSL2 连接)

3. 点击完成，确保 VcXsrv 在系统托盘运行

#### 步骤 2: 在 WSL2 中配置显示

```bash
# 1. 确保安装了必要的图形支持
sudo apt install -y weston

# 2. 设置 DISPLAY 环境变量（自动检测 Windows IP）
export DISPLAY=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}'):0

# 3. 或者手动设置（如果上述方法无效）
# export DISPLAY=172.17.224.1:0  # 替换为你的 Windows IP

# 4. 添加到 ~/.bashrc 使其永久生效
echo 'export DISPLAY=$(cat /etc/resolv.conf | grep nameserver | awk '"'"'{print $2}'"'"'):0' >> ~/.bashrc

# 5. 测试 X 连接
sudo apt install -y x11-apps
xclock  # 应该显示一个时钟窗口
```

#### 步骤 3: 启动 Waydroid

```bash
# 1. 确保 DISPLAY 已设置
echo $DISPLAY  # 应该显示类似 172.17.224.1:0

# 2. 启动 Waydroid 会话
waydroid session start

# 3. 在另一个终端启动完整 UI
waydroid show-full-ui
```

#### 防火墙设置
如果仍然无法显示，检查 Windows 防火墙：
1. 打开 Windows  Defender 防火墙
2. 允许 VcXsrv 通过防火墙
3. 或者临时关闭防火墙测试

---

## 参考资源

- [微软 WSL2 内核源码](https://github.com/microsoft/WSL2-Linux-Kernel)
- [Waydroid 官方文档](https://docs.waydro.id/)
- [WSL2 内核编译官方指南](https://docs.microsoft.com/en-us/windows/wsl/kernel-release-notes)
- [Waydroid GitHub Issues](https://github.com/waydroid/waydroid/issues)

---

*本文档由 AI 助手生成，如有问题请参考官方文档或提交 Issue。*
