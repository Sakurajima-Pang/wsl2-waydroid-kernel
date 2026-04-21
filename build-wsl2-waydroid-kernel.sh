#!/bin/bash

set -e

# WSL2 Waydroid 内核一键编译脚本
# 作者: AI Assistant
# 版本: 1.0

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
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
    local available=$(df /home | tail -1 | awk '{print $4}')
    local required=$((20 * 1024 * 1024)) # 20GB in KB
    local available_gb=$((available / 1024 / 1024))
    
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
    )
    
    log_info "更新软件包列表..."
    sudo apt update
    
    log_info "安装依赖包..."
    sudo apt install -y "${deps[@]}"
    
    log_info "依赖安装完成"
}

# 下载内核源码
download_kernel() {
    log_step "下载 WSL2 内核源码..."
    
    mkdir -p ~/wsl2-kernel-build
    cd ~/wsl2-kernel-build
    
    if [ -d "WSL2-Linux-Kernel" ]; then
        log_warn "内核源码目录已存在"
        read -p "是否重新下载? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "删除旧目录..."
            rm -rf WSL2-Linux-Kernel
            git clone --depth 1 https://github.com/microsoft/WSL2-Linux-Kernel.git
        else
            log_info "更新现有仓库..."
            cd WSL2-Linux-Kernel
            git fetch --tags
        fi
    else
        log_info "克隆内核仓库..."
        git clone --depth 1 https://github.com/microsoft/WSL2-Linux-Kernel.git
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
    
    # 定义需要启用的配置
    declare -a enable_configs=(
        "CONFIG_ANDROID"
        "CONFIG_ANDROID_BINDER_IPC"
        "CONFIG_ANDROID_BINDERFS"
        "CONFIG_ASHMEM"
        "CONFIG_ANDROID_SIMPLE_LMK"
        "CONFIG_SW_SYNC"
        "CONFIG_SYNC_FILE"
        "CONFIG_BINDERFS"
        "CONFIG_MEMCG"
        "CONFIG_CGROUP_DEVICE"
    )
    
    for cfg in "${enable_configs[@]}"; do
        # 删除旧配置
        sed -i "/^${cfg}/d" .config
        # 添加新配置
        echo "${cfg}=y" >> .config
    done
    
    # 添加 binder 设备配置
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
    
    log_info "使用 ${cpu_count} 个 CPU 核心进行编译"
    
    # 编译
    if make -j"${cpu_count}" 2>&1 | tee build.log | while read line; do
        echo "$line" | grep -E "^(  CC|  LD|  AR|  CHK|Kernel:|Building)" | head -5
    done; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        
        log_info "内核编译成功！"
        log_info "编译耗时: ${minutes} 分 ${seconds} 秒"
    else
        log_error "内核编译失败"
        log_error "请查看 build.log 了解详细错误信息"
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
    local win_path="/mnt/c/wsl2-kernel"
    
    if [ ! -d "$win_path" ]; then
        log_info "创建目录: C:\\wsl2-kernel"
        mkdir -p "$win_path"
    fi
    
    # 备份旧内核
    if [ -f "${win_path}/bzImage-waydroid" ]; then
        log_info "备份旧内核..."
        cp "${win_path}/bzImage-waydroid" "${win_path}/bzImage-waydroid.backup.$(date +%Y%m%d%H%M%S)"
    fi
    
    # 复制内核
    log_info "复制内核到 Windows..."
    cp arch/x86/boot/bzImage "${win_path}/bzImage-waydroid"
    cp .config "${win_path}/config-waydroid"
    
    # 记录编译信息
    cat > "${win_path}/build-info.txt" << EOF
编译时间: $(date)
内核版本: $(make kernelrelease 2>/dev/null || echo 'Unknown')
Git 提交: $(git rev-parse --short HEAD 2>/dev/null || echo 'Unknown')
编译主机: $(uname -a)
EOF
    
    log_info "内核已安装到: C:\\wsl2-kernel\\bzImage-waydroid"
}

# 生成 WSL 配置
generate_wsl_config() {
    log_step "生成 WSL 配置..."
    
    local win_path="/mnt/c/wsl2-kernel"
    local config_file="${win_path}/.wslconfig-template"
    
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
    
    cat > "$config_file" << EOF
# WSL2 配置文件
# 将此内容复制到 %USERPROFILE%\\.wslconfig (Windows 用户目录下)

[wsl2]
# 自定义内核路径
kernel=C:\\\\wsl2-kernel\\\\bzImage-waydroid

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
    log_info "位置: C:\\wsl2-kernel\\.wslconfig-template"
    
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
    local verify_script="/mnt/c/wsl2-kernel/verify-waydroid.sh"
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
    for cfg in CONFIG_ANDROID CONFIG_ANDROID_BINDER_IPC CONFIG_ANDROID_BINDERFS CONFIG_ASHMEM; do
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
    log_info "验证脚本已保存到: C:\\wsl2-kernel\\verify-waydroid.sh"
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
