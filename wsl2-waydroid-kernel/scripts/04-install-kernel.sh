#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
BUILD_DIR="$PROJECT_DIR/build"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/04-install-kernel-$(date +%Y%m%d-%H%M%S).log"

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

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   安装 WSL2 内核 v1.0.0${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "" | tee -a "$LOG_FILE"
}

print_footer() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${BLUE}========================================${NC}"
}

get_windows_home() {
    if [ -n "$WIN_HOME" ]; then
        echo "$WIN_HOME"
    elif command -v wslpath &> /dev/null; then
        wslpath "$USERPROFILE"
    else
        local win_user
        win_user=$(whoami)
        echo "/mnt/c/Users/$win_user"
    fi
}

find_kernel_image() {
    log_info "查找内核镜像..."
    
    local kernel_image=""
    
    if [ -f "$BUILD_DIR/bzImage-waydroid" ]; then
        kernel_image="$BUILD_DIR/bzImage-waydroid"
    elif [ -f "$BUILD_DIR/bzImage" ]; then
        kernel_image="$BUILD_DIR/bzImage"
    elif [ -f "$BUILD_DIR/WSL2-Linux-Kernel/arch/x86/boot/bzImage" ]; then
        kernel_image="$BUILD_DIR/WSL2-Linux-Kernel/arch/x86/boot/bzImage"
    fi
    
    if [ -n "$kernel_image" ]; then
        log_success "找到内核镜像: $kernel_image"
        echo "$kernel_image"
        return 0
    else
        log_error "找不到内核镜像"
        log_info "请确认已运行 03-build-kernel.sh 成功编译内核"
        return 1
    fi
}

backup_current_kernel() {
    log_info "备份当前配置..."
    
    local windows_home
    windows_home=$(get_windows_home)
    local backup_dir="$windows_home/wsl2-waydroid-backup"
    
    mkdir -p "$backup_dir"
    
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    
    if [ -f "$windows_home/.wslconfig" ]; then
        cp "$windows_home/.wslconfig" "$backup_dir/.wslconfig.backup-$timestamp"
        log_success "已备份 .wslconfig"
    fi
    
    local current_kernel
    current_kernel=$(uname -r)
    echo "$current_kernel" > "$backup_dir/kernel-version-$timestamp.txt"
    log_success "已记录当前内核版本: $current_kernel"
    
    echo "BACKUP_DIR=$backup_dir" >> "$LOG_FILE"
    echo "BACKUP_TIMESTAMP=$timestamp" >> "$LOG_FILE"
}

copy_kernel_to_windows() {
    log_info "复制内核到 Windows..."
    
    local kernel_image
    kernel_image=$(find_kernel_image)
    
    local windows_home
    windows_home=$(get_windows_home)
    local windows_kernel_dir="$windows_home/wsl2-waydroid-kernel"
    
    mkdir -p "$windows_kernel_dir"
    
    local target_kernel="$windows_kernel_dir/bzImage-waydroid"
    cp "$kernel_image" "$target_kernel"
    
    log_success "内核已复制到: $target_kernel"
    
    local kernel_size
    kernel_size=$(du -h "$target_kernel" | cut -f1)
    log_success "内核大小: $kernel_size"
    
    echo "WINDOWS_KERNEL_PATH=$target_kernel" >> "$LOG_FILE"
    echo "WINDOWS_KERNEL_SIZE=$kernel_size" >> "$LOG_FILE"
    
    echo "$target_kernel"
}

configure_wslconfig() {
    log_info "配置 .wslconfig..."
    
    local windows_home
    windows_home=$(get_windows_home)
    local wslconfig="$windows_home/.wslconfig"
    local windows_kernel_path
    windows_kernel_path=$(find_kernel_image)
    
    local windows_style_path
    if command -v wslpath &> /dev/null; then
        windows_style_path=$(wslpath -w "$windows_kernel_path" | sed 's/\\/\\\\/g')
    else
        windows_style_path=$(echo "$windows_kernel_path" | sed 's|^/mnt/c|C:|; s|/|\\\\|g')
    fi
    
    log_info "Windows 内核路径: $windows_style_path"
    
    if [ -f "$wslconfig" ]; then
        log_info "备份现有 .wslconfig..."
        cp "$wslconfig" "$wslconfig.backup.$(date +%Y%m%d-%H%M%S)"
        
        if grep -q "^\s*kernel\s*=" "$wslconfig"; then
            log_info "更新现有 kernel 配置..."
            sed -i "s|^\s*kernel\s*=.*|kernel=$windows_style_path|" "$wslconfig"
        else
            log_info "添加 kernel 配置..."
            if grep -q "^\s*\[wsl2\]" "$wslconfig"; then
                sed -i "/^\s*\[wsl2\]/a kernel=$windows_style_path" "$wslconfig"
            else
                cat >> "$wslconfig" << EOF

[wsl2]
kernel=$windows_style_path
EOF
            fi
        fi
    else
        log_info "创建新的 .wslconfig..."
        cat > "$wslconfig" << EOF
[wsl2]
kernel=$windows_style_path
memory=8GB
processors=4
EOF
    fi
    
    log_success ".wslconfig 配置完成"
    log_info "配置文件内容:"
    cat "$wslconfig" | tee -a "$LOG_FILE"
    
    echo "WSLCONFIG_PATH=$wslconfig" >> "$LOG_FILE"
}

restart_wsl() {
    log_info "重启 WSL..."
    
    log_warning "WSL 即将关闭并重启"
    log_info "重启后请重新打开 WSL 终端"
    
    read -p "确认现在重启 WSL? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [ -n "$REPLY" ]; then
        log_info "请稍后手动重启 WSL:"
        log_info "  在 PowerShell 中执行: wsl --shutdown"
        return 0
    fi
    
    log_info "关闭 WSL..."
    if command -v wsl.exe &> /dev/null; then
        wsl.exe --shutdown 2>&1 | tee -a "$LOG_FILE" || true
    else
        log_warning "无法自动关闭 WSL，请手动执行: wsl --shutdown"
    fi
    
    log_success "WSL 已关闭"
    log_info "请等待几秒钟后重新打开 WSL 终端"
    log_info "新内核将在下次启动时生效"
}

verify_new_kernel() {
    log_info "验证新内核..."
    
    local current_kernel
    current_kernel=$(uname -r)
    
    log_info "当前内核版本: $current_kernel"
    
    if echo "$current_kernel" | grep -q "waydroid\|custom"; then
        log_success "新内核已生效"
        echo "KERNEL_VERIFIED=true" >> "$LOG_FILE"
        return 0
    else
        log_warning "内核版本未显示自定义标识"
        log_info "这通常不影响功能，只要 binder 模块可用"
        echo "KERNEL_VERIFIED=partial" >> "$LOG_FILE"
        return 0
    fi
}

main() {
    print_header
    
    log_info "开始安装 WSL2 内核"
    log_info "日志文件: $LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    log_warning "此步骤需要管理员权限"
    log_info "内核将被安装到 Windows 系统"
    
    read -p "确认继续安装? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [ -n "$REPLY" ]; then
        log_info "用户取消安装"
        exit 0
    fi
    
    local kernel_image
    if ! kernel_image=$(find_kernel_image); then
        exit 1
    fi
    echo "" | tee -a "$LOG_FILE"
    
    backup_current_kernel
    echo "" | tee -a "$LOG_FILE"
    
    copy_kernel_to_windows
    echo "" | tee -a "$LOG_FILE"
    
    configure_wslconfig
    echo "" | tee -a "$LOG_FILE"
    
    restart_wsl
    
    echo "" | tee -a "$LOG_FILE"
    log_success "内核安装完成"
    log_info "WSL 重启后，请按顺序执行:"
    log_info "  1. bash 05-install-waydroid.sh  (安装 Waydroid)"
    log_info "  2. bash 06-verify.sh           (验证安装)"
    
    print_footer
}

main "$@"
