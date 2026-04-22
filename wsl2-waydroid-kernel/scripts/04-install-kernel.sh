#!/bin/bash

# 不使用 set -e，避免意外退出

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
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    echo "[✓] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
    echo "[!] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    echo "[✗] $1" >> "$LOG_FILE" 2>/dev/null || true
}

# 辅助函数：输出到屏幕和日志
log_echo() {
    echo "$1"
    echo "$1" >> "$LOG_FILE" 2>/dev/null || true
}

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   安装 WSL2 内核 v2.0.0${NC}"
    echo -e "${BLUE}========================================${NC}"
    log_echo ""
}

print_footer() {
    log_echo ""
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
    log_info "查找内核镜像..." >&2
    
    local kernel_image=""
    
    if [ -f "$BUILD_DIR/bzImage-waydroid" ]; then
        kernel_image="$BUILD_DIR/bzImage-waydroid"
    elif [ -f "$BUILD_DIR/bzImage" ]; then
        kernel_image="$BUILD_DIR/bzImage"
    elif [ -f "$BUILD_DIR/WSL2-Linux-Kernel/arch/x86/boot/bzImage" ]; then
        kernel_image="$BUILD_DIR/WSL2-Linux-Kernel/arch/x86/boot/bzImage"
    fi
    
    if [ -n "$kernel_image" ]; then
        log_success "找到内核镜像: $kernel_image" >&2
        printf '%s\n' "$kernel_image"
        return 0
    else
        log_error "找不到内核镜像" >&2
        log_info "请确认已运行 03-build-kernel.sh 成功编译内核" >&2
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
    
    # 使用复制到 Windows 的本地路径，而不是 WSL 网络路径
    local windows_kernel_dir="$windows_home/wsl2-waydroid-kernel"
    local windows_kernel_path="$windows_kernel_dir/bzImage-waydroid"
    
    # 检查内核文件是否已复制到 Windows
    if [ ! -f "$windows_kernel_path" ]; then
        log_error "内核文件未找到: $windows_kernel_path"
        log_info "请先运行 copy_kernel_to_windows 复制内核"
        return 1
    fi
    
    # 转换为 Windows 路径格式 (C:\Users\...)
    local windows_style_path
    windows_style_path=$(echo "$windows_kernel_path" | sed 's|^/mnt/c/|C:\\\\|; s|/|\\\\\\\\|g')
    
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
    cat "$wslconfig"
    cat "$wslconfig" >> "$LOG_FILE" 2>/dev/null || true
    
    echo "WSLCONFIG_PATH=$wslconfig" >> "$LOG_FILE"
}

restart_wsl() {
    log_info "重启 WSL..."
    
    log_warning "WSL 即将关闭并重启"
    log_info "重启后请重新打开 WSL 终端"
    
    if [ -z "$SKIP_CONFIRM" ]; then
        read -p "确认现在重启 WSL? (Y/n): " -n 1 -r < /dev/tty 2>/dev/null || read -p "确认现在重启 WSL? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]] && [ -n "$REPLY" ]; then
            log_info "请稍后手动重启 WSL:"
            log_info "  在 PowerShell 中执行: wsl --shutdown"
            return 0
        fi
    else
        log_info "自动重启 WSL (SKIP_CONFIRM 已设置)"
    fi
    
    log_info "关闭 WSL..."
    if command -v wsl.exe &> /dev/null; then
        wsl.exe --shutdown 2>&1 >> "$LOG_FILE" 2>/dev/null || true
    else
        log_warning "无法自动关闭 WSL，请手动执行: wsl --shutdown"
    fi
    
    log_success "WSL 已关闭"
    log_info "请等待几秒钟后重新打开 WSL 终端"
    log_info "新内核将在下次启动时生效"
}

main() {
    print_header
    
    log_info "开始安装 WSL2 内核"
    log_info "日志文件: $LOG_FILE"
    log_echo ""
    
    log_warning "此步骤需要管理员权限"
    log_info "内核将被安装到 Windows 系统"
    
    if [ -z "$SKIP_CONFIRM" ]; then
        read -p "确认继续安装? (Y/n): " -n 1 -r < /dev/tty 2>/dev/null || read -p "确认继续安装? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]] && [ -n "$REPLY" ]; then
            log_info "用户取消安装"
            exit 0
        fi
    else
        log_info "跳过确认 (SKIP_CONFIRM 已设置)"
    fi
    
    local kernel_image
    if ! kernel_image=$(find_kernel_image); then
        exit 1
    fi
    log_echo ""
    
    backup_current_kernel
    log_echo ""
    
    copy_kernel_to_windows
    log_echo ""
    
    configure_wslconfig
    log_echo ""
    
    restart_wsl
    
    log_echo ""
    log_success "内核安装完成"
    log_info "WSL 重启后，请按顺序执行:"
    log_info "  1. bash 05-install-waydroid.sh  (安装 Waydroid)"
    log_info "  2. bash 06-verify.sh           (验证安装)"
    
    print_footer
}

main "$@"
