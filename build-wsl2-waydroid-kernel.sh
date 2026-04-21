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
    # sed替换中，'\\\\' 表示替换为两个反斜杠，最终在配置文件中显示为双反斜杠
    local win_path=$(echo "${WIN_KERNEL_PATH}" | sed 's|/mnt/\([a-zA-Z]\)/|\1:\\\\|' | sed 's|/|\\\\|g')
    # 追加内核文件名，使用双反斜杠
    win_path="${win_path}\\bzImage-waydroid"
    
    cat > "$config_file" << EOF
# WSL2 配置文件
# 将此内容复制到 %USERPROFILE%\.wslconfig (Windows 用户目录下)

[wsl2]
# 自定义内核路径
kernel=${win_path}

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

    # 定义需要检查的配置（与提示词和指南中要求的模块一致）
    declare -a required_configs=(
        "CONFIG_ANDROID"
        "CONFIG_ANDROID_BINDER_IPC"
        "CONFIG_ANDROID_BINDERFS"
        "CONFIG_ASHMEM"
        "CONFIG_MEMCG"
        "CONFIG_CGROUP_DEVICE"
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

    # 检查 CONFIG_ANDROID_BINDER_DEVICES 字符串配置
    local binder_devices_config
    if [ "$config_source" = "/proc/config.gz" ]; then
        binder_devices_config=$(zcat /proc/config.gz 2>/dev/null | grep "^CONFIG_ANDROID_BINDER_DEVICES=" || echo "")
    else
        binder_devices_config=$(grep "^CONFIG_ANDROID_BINDER_DEVICES=" "$config_source" || echo "")
    fi

    if echo "$binder_devices_config" | grep -q "binder.*hwbinder.*vndbinder"; then
        log_pass "$binder_devices_config"
    else
        log_fail "CONFIG_ANDROID_BINDER_DEVICES 未正确设置"
    fi
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
