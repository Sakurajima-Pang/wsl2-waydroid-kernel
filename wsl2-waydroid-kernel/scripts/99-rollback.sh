#!/bin/bash

# 不使用 set -e，避免意外退出

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/99-rollback-$(date +%Y%m%d-%H%M%S).log"

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
    echo -e "${BLUE}   回滚 WSL2 配置 v2.0.0${NC}"
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

show_menu() {
    echo "请选择要执行的操作:"
    echo ""
    echo "1) 恢复默认内核配置"
    echo "2) 清理编译产物"
    echo "3) 卸载 Waydroid"
    echo "4) 执行所有回滚操作"
    echo "5) 取消"
    echo ""
}

restore_default_kernel() {
    log_info "恢复默认内核配置..."
    
    local windows_home
    windows_home=$(get_windows_home)
    local wslconfig="$windows_home/.wslconfig"
    
    if [ -f "$wslconfig" ]; then
        log_info "备份当前 .wslconfig..."
        cp "$wslconfig" "$wslconfig.rollback-backup.$(date +%Y%m%d-%H%M%S)"
        
        log_info "移除 kernel 配置..."
        if grep -q "^\s*kernel\s*=" "$wslconfig"; then
            sed -i '/^\s*kernel\s*=.*/d' "$wslconfig"
            log_success "已移除 kernel 配置行"
        fi
        
        log_info "检查 .wslconfig 是否为空..."
        if [ ! -s "$wslconfig" ] || ! grep -q '[^[:space:]]' "$wslconfig"; then
            log_info ".wslconfig 为空，删除文件..."
            rm -f "$wslconfig"
        fi
        
        log_success "默认内核配置已恢复"
    else
        log_info ".wslconfig 不存在，无需恢复"
    fi
    
    log_warning "需要重启 WSL 才能生效"
    read -p "是否现在重启 WSL? (Y/n): " -n 1 -r < /dev/tty 2>/dev/null || read -p "是否现在重启 WSL? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]] || [ -z "$REPLY" ]; then
        log_info "关闭 WSL..."
        if command -v wsl.exe &> /dev/null; then
            wsl.exe --shutdown 2>&1 >> "$LOG_FILE" 2>/dev/null || true
        fi
        log_success "WSL 已关闭，请重新打开 WSL 终端"
    fi
    
    echo "KERNEL_RESTORED=true" >> "$LOG_FILE"
}

cleanup_build_artifacts() {
    log_info "清理编译产物..."
    
    local build_dir="$PROJECT_DIR/build"
    local total_freed=0
    
    if [ -d "$build_dir" ]; then
        local build_size
        build_size=$(du -sb "$build_dir" 2>/dev/null | cut -f1 || echo "0")
        total_freed=$((total_freed + build_size))
        
        log_info "删除构建目录: $build_dir"
        rm -rf "$build_dir"
        log_success "构建目录已删除"
    fi
    
    local logs_size=0
    if [ -d "$LOG_DIR" ]; then
        logs_size=$(du -sb "$LOG_DIR" 2>/dev/null | cut -f1 || echo "0")
        read -p "是否删除日志文件? (y/N): " -n 1 -r < /dev/tty 2>/dev/null || read -p "是否删除日志文件? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            total_freed=$((total_freed + logs_size))
            rm -rf "$LOG_DIR"
            log_success "日志文件已删除"
        else
            log_info "保留日志文件"
        fi
    fi
    
    local freed_mb=$((total_freed / 1024 / 1024))
    log_success "共释放约 ${freed_mb}MB 磁盘空间"
    
    echo "CLEANUP_COMPLETED=true" >> "$LOG_FILE"
    echo "SPACE_FREED_MB=$freed_mb" >> "$LOG_FILE"
}

uninstall_waydroid() {
    log_info "卸载 Waydroid..."
    
    log_warning "这将删除 Waydroid 及其所有数据"
    read -p "确认卸载 Waydroid? (y/N): " -n 1 -r < /dev/tty 2>/dev/null || read -p "确认卸载 Waydroid? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "取消卸载"
        return 0
    fi
    
    log_info "停止 Waydroid 服务..."
    sudo systemctl stop waydroid-container 2>&1 >> "$LOG_FILE" 2>/dev/null || true
    sudo systemctl disable waydroid-container 2>&1 >> "$LOG_FILE" 2>/dev/null || true
    
    log_info "停止 Waydroid 会话..."
    waydroid session stop 2>&1 >> "$LOG_FILE" 2>/dev/null || true
    
    log_info "删除 Waydroid 数据..."
    sudo rm -rf /var/lib/waydroid 2>&1 >> "$LOG_FILE" 2>/dev/null || true
    rm -rf "$HOME/.local/share/waydroid" 2>&1 >> "$LOG_FILE" 2>/dev/null || true
    
    log_info "卸载 Waydroid 包..."
    local distro
    distro=$(grep "^ID=" /etc/os-release 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "unknown")
    
    case "$distro" in
        ubuntu|debian)
            sudo apt-get remove -y waydroid 2>&1 >> "$LOG_FILE" 2>/dev/null || true
            sudo apt-get autoremove -y 2>&1 >> "$LOG_FILE" 2>/dev/null || true
            ;;
        fedora)
            sudo dnf remove -y waydroid 2>&1 >> "$LOG_FILE" 2>/dev/null || true
            ;;
        arch)
            sudo pacman -R waydroid 2>&1 >> "$LOG_FILE" 2>/dev/null || true
            ;;
    esac
    
    log_info "删除 Waydroid 仓库..."
    sudo rm -f /etc/apt/sources.list.d/waydroid.list 2>&1 >> "$LOG_FILE" 2>/dev/null || true
    sudo rm -f /usr/share/keyrings/waydroid.gpg 2>&1 >> "$LOG_FILE" 2>/dev/null || true
    
    log_success "Waydroid 已卸载"
    echo "WAYDROID_UNINSTALLED=true" >> "$LOG_FILE"
}

full_rollback() {
    log_info "执行完整回滚..."
    
    restore_default_kernel
    log_echo ""
    
    cleanup_build_artifacts
    log_echo ""
    
    uninstall_waydroid
    
    log_success "完整回滚完成"
    log_info "系统已恢复到默认状态"
}

show_summary() {
    log_echo ""
    echo -e "${BLUE}----------------------------------------${NC}"
    echo "----------------------------------------" >> "$LOG_FILE" 2>/dev/null || true
    log_info "回滚操作摘要:"
    log_echo ""
    
    if grep -q "KERNEL_RESTORED=true" "$LOG_FILE" 2>/dev/null; then
        log_success "✓ 内核配置已恢复"
    fi
    
    if grep -q "CLEANUP_COMPLETED=true" "$LOG_FILE" 2>/dev/null; then
        local freed
        freed=$(grep "SPACE_FREED_MB=" "$LOG_FILE" | cut -d'=' -f2 || echo "0")
        log_success "✓ 编译产物已清理 (释放 ${freed}MB)"
    fi
    
    if grep -q "WAYDROID_UNINSTALLED=true" "$LOG_FILE" 2>/dev/null; then
        log_success "✓ Waydroid 已卸载"
    fi
    
    log_echo ""
    log_info "如需重新安装，请按顺序运行:"
    log_info "  bash 03-build-kernel.sh"
    log_info "  bash 04-install-kernel.sh"
    log_info "  bash 05-install-waydroid.sh"
}

main() {
    print_header
    
    log_info "WSL2 Waydroid 回滚工具"
    log_info "日志文件: $LOG_FILE"
    log_echo ""
    
    show_menu
    
    read -p "请输入选项 (1-5): " choice
    echo
    
    case "$choice" in
        1)
            restore_default_kernel
            ;;
        2)
            cleanup_build_artifacts
            ;;
        3)
            uninstall_waydroid
            ;;
        4)
            full_rollback
            ;;
        5)
            log_info "取消操作"
            exit 0
            ;;
        *)
            log_error "无效选项"
            exit 1
            ;;
    esac
    
    show_summary
    print_footer
    
    log_info "日志已保存到: $LOG_FILE"
}

main "$@"
