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
    local wsl_path="$(echo "$win_userprofile" | tr '\\' '/' | sed 's|^[Cc]:|/mnt/c|' | sed 's|^[Dd]:|/mnt/d|')"
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
        i=$((i+1))
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
    local win_path=$(echo "${WIN_KERNEL_PATH}" | sed 's|/mnt/c/|C:\\|' | sed 's|/|\\|g')

    if [ ! -f "$wslconfig_path" ] 2>/dev/null; then
        log_info "创建 WSL 配置文件..."
        cat > "$wslconfig_path" << EOF
[wsl2]
kernel=${win_path}\\bzImage-waydroid
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
