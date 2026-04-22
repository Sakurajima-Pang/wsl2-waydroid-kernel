#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/05-install-waydroid-$(date +%Y%m%d-%H%M%S).log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
}

log_progress() {
    echo -e "${BLUE}[PROGRESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   安装 Waydroid v2.0.0${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "" | tee -a "$LOG_FILE"
}

print_footer() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${BLUE}========================================${NC}"
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"'
    else
        echo "unknown"
    fi
}

add_waydroid_repository() {
    log_info "添加 Waydroid 仓库..."
    
    local distro
    distro=$(detect_distro)
    
    case "$distro" in
        ubuntu|debian)
            log_info "为 Ubuntu/Debian 添加仓库..."
            
            if ! command -v curl &> /dev/null; then
                sudo apt-get update
                sudo apt-get install -y curl
            fi
            
            curl https://repo.waydro.id/waydroid.gpg | sudo gpg --dearmor -o /usr/share/keyrings/waydroid.gpg 2>&1 | tee -a "$LOG_FILE"
            
            local ubuntu_version
            ubuntu_version=$(grep "^VERSION_CODENAME=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
            
            echo "deb [signed-by=/usr/share/keyrings/waydroid.gpg] https://repo.waydro.id/ ${ubuntu_version} main" | sudo tee /etc/apt/sources.list.d/waydroid.list
            
            sudo apt-get update 2>&1 | tee -a "$LOG_FILE"
            log_success "Waydroid 仓库添加完成"
            ;;
        *)
            log_warning "非 Ubuntu/Debian 系统，尝试通用安装方法"
            log_info "请参考 Waydroid 官方文档获取其他发行版的安装方法"
            ;;
    esac
}

install_waydroid_package() {
    log_info "安装 Waydroid..."
    
    local distro
    distro=$(detect_distro)
    
    case "$distro" in
        ubuntu|debian)
            sudo apt-get install -y waydroid 2>&1 | tee -a "$LOG_FILE"
            ;;
        *)
            log_error "不支持的发行版: $distro"
            log_info "请手动安装 Waydroid"
            return 1
            ;;
    esac
    
    if command -v waydroid &> /dev/null; then
        local version
        version=$(waydroid --version 2>/dev/null || echo "unknown")
        log_success "Waydroid 安装完成 (版本: $version)"
        echo "WAYDROID_VERSION=$version" >> "$LOG_FILE"
        return 0
    else
        log_error "Waydroid 安装失败"
        return 1
    fi
}

install_dependencies() {
    log_info "安装 Waydroid 依赖..."
    
    local packages=(
        "lxc"
        "python3"
        "python3-gi"
        "gir1.2-gtk-3.0"
        "dbus"
        "policykit-1"
        "iptables"
        "dnsmasq-base"
    )
    
    local distro
    distro=$(detect_distro)
    
    case "$distro" in
        ubuntu|debian)
            sudo apt-get install -y "${packages[@]}" 2>&1 | tee -a "$LOG_FILE"
            ;;
    esac
    
    log_success "依赖安装完成"
}

initialize_waydroid() {
    log_info "初始化 Waydroid..."
    
    log_info "选择 Android 镜像类型:"
    echo "1) LineageOS (默认，无 Google 服务)"
    echo "2) LineageOS with GAPPS (包含 Google 服务)"
    read -p "请选择 (1/2): " -n 1 -r < /dev/tty 2>/dev/null || read -p "请选择 (1/2): " -n 1 -r
    echo
    
    local gapps_option=""
    if [[ $REPLY == "2" ]]; then
        gapps_option="-g"
        log_info "将安装包含 GAPPS 的镜像"
    else
        log_info "将安装默认镜像（无 GAPPS）"
    fi
    
    log_info "开始初始化（这可能需要 10-20 分钟）..."
    log_info "正在下载 Android 系统镜像，请耐心等待..."
    
    if sudo waydroid init $gapps_option 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Waydroid 初始化完成"
        echo "WAYDROID_INIT_SUCCESS=true" >> "$LOG_FILE"
        return 0
    else
        log_error "Waydroid 初始化失败"
        echo "WAYDROID_INIT_SUCCESS=false" >> "$LOG_FILE"
        return 1
    fi
}

start_waydroid_service() {
    log_info "启动 Waydroid 服务..."
    
    if systemctl is-active --quiet waydroid-container 2>/dev/null; then
        log_success "Waydroid 服务已在运行"
    else
        log_info "启动 Waydroid 容器服务..."
        sudo systemctl start waydroid-container 2>&1 | tee -a "$LOG_FILE" || true
        
        sleep 2
        
        if systemctl is-active --quiet waydroid-container 2>/dev/null; then
            log_success "Waydroid 服务已启动"
        else
            log_warning "Waydroid 服务可能未正确启动"
            log_info "可以尝试手动启动: sudo systemctl start waydroid-container"
        fi
    fi
    
    sudo systemctl enable waydroid-container 2>&1 | tee -a "$LOG_FILE" || true
}

check_binder_devices() {
    log_info "检查 binder 设备..."
    
    local binder_devices=(
        "/dev/binder"
        "/dev/hwbinder"
        "/dev/vndbinder"
    )
    
    local all_exist=true
    for device in "${binder_devices[@]}"; do
        if [ -e "$device" ]; then
            log_success "找到设备: $device"
        else
            log_warning "缺少设备: $device"
            all_exist=false
        fi
    done
    
    if [ "$all_exist" = false ]; then
        log_warning "部分 binder 设备不存在"
        log_info "尝试加载 binder 模块..."
        
        sudo modprobe binder_linux devices="binder,hwbinder,vndbinder" 2>&1 | tee -a "$LOG_FILE" || true
        
        sleep 1
        
        for device in "${binder_devices[@]}"; do
            if [ -e "$device" ]; then
                log_success "加载后找到设备: $device"
            else
                log_error "仍然缺少设备: $device"
            fi
        done
    fi
}

setup_binderfs() {
    log_info "设置 binderfs..."
    
    if [ -d /dev/binderfs ]; then
        log_success "binderfs 已挂载"
        return 0
    fi
    
    log_info "创建 binderfs 目录..."
    sudo mkdir -p /dev/binderfs
    
    log_info "挂载 binderfs..."
    if sudo mount -t binder binder /dev/binderfs 2>&1 | tee -a "$LOG_FILE"; then
        log_success "binderfs 挂载成功"
        
        log_info "创建 binder 设备符号链接..."
        sudo ln -sf /dev/binderfs/binder /dev/binder 2>/dev/null || true
        sudo ln -sf /dev/binderfs/hwbinder /dev/hwbinder 2>/dev/null || true
        sudo ln -sf /dev/binderfs/vndbinder /dev/vndbinder 2>/dev/null || true
        
        log_success "binder 设备符号链接创建完成"
    else
        log_warning "binderfs 挂载失败，尝试使用 modprobe..."
        sudo modprobe binder_linux devices="binder,hwbinder,vndbinder" 2>&1 | tee -a "$LOG_FILE" || true
    fi
}

show_post_install_info() {
    echo "" | tee -a "$LOG_FILE"
    log_success "Waydroid 安装完成"
    echo "" | tee -a "$LOG_FILE"
    
    log_info "使用方法:"
    echo "" | tee -a "$LOG_FILE"
    echo "  1. 启动 Waydroid 会话:" | tee -a "$LOG_FILE"
    echo "     waydroid session start" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "  2. 在新终端中启动图形界面:" | tee -a "$LOG_FILE"
    echo "     waydroid show-full-ui" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "  3. 常用命令:" | tee -a "$LOG_FILE"
    echo "     waydroid status       # 查看状态" | tee -a "$LOG_FILE"
    echo "     waydroid log          # 查看日志" | tee -a "$LOG_FILE"
    echo "     waydroid session stop # 停止会话" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "  4. 服务管理:" | tee -a "$LOG_FILE"
    echo "     sudo systemctl start waydroid-container  # 启动服务" | tee -a "$LOG_FILE"
    echo "     sudo systemctl stop waydroid-container   # 停止服务" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    log_info "提示: 首次启动可能需要一些时间来初始化 Android 系统"
}

main() {
    print_header
    
    log_info "开始安装 Waydroid"
    log_info "日志文件: $LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    read -p "确认开始安装 Waydroid? (Y/n): " -n 1 -r < /dev/tty 2>/dev/null || read -p "确认开始安装 Waydroid? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [ -n "$REPLY" ]; then
        log_info "用户取消安装"
        exit 0
    fi
    
    check_binder_devices
    echo "" | tee -a "$LOG_FILE"
    
    setup_binderfs
    echo "" | tee -a "$LOG_FILE"
    
    add_waydroid_repository
    echo "" | tee -a "$LOG_FILE"
    
    install_dependencies
    echo "" | tee -a "$LOG_FILE"
    
    install_waydroid_package
    echo "" | tee -a "$LOG_FILE"
    
    initialize_waydroid
    echo "" | tee -a "$LOG_FILE"
    
    start_waydroid_service
    echo "" | tee -a "$LOG_FILE"
    
    show_post_install_info
    
    log_info "建议运行验证脚本: bash 06-verify.sh"
    
    print_footer
}

main "$@"
