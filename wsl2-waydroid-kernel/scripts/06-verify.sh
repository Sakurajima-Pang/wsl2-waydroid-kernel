#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/06-verify-$(date +%Y%m%d-%H%M%S).log"

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
    echo -e "${BLUE}   Waydroid 安装验证报告 v1.0.0${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "" | tee -a "$LOG_FILE"
}

print_footer() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${BLUE}========================================${NC}"
}

verify_kernel_version() {
    log_info "检查内核版本..."
    
    local kernel_version
    kernel_version=$(uname -r)
    
    log_info "当前内核: $kernel_version"
    echo "KERNEL_VERSION=$kernel_version" >> "$LOG_FILE"
    
    if echo "$kernel_version" | grep -q "WSL2"; then
        log_success "WSL2 内核运行中"
        return 0
    else
        log_warning "可能不是 WSL2 内核"
        return 1
    fi
}

verify_kernel_modules() {
    log_info "检查内核模块..."
    
    local modules=(
        "android"
        "binder"
        "ashmem"
    )
    
    local all_loaded=true
    for module in "${modules[@]}"; do
        if lsmod | grep -q "$module"; then
            log_success "模块已加载: $module"
        else
            log_warning "模块未加载: $module"
            all_loaded=false
        fi
    done
    
    if [ "$all_loaded" = true ]; then
        echo "KERNEL_MODULES_LOADED=true" >> "$LOG_FILE"
        return 0
    else
        echo "KERNEL_MODULES_LOADED=partial" >> "$LOG_FILE"
        return 0
    fi
}

verify_binder_devices() {
    log_info "检查 binder 设备..."
    
    local binder_devices=(
        "/dev/binder"
        "/dev/hwbinder"
        "/dev/vndbinder"
    )
    
    local all_exist=true
    for device in "${binder_devices[@]}"; do
        if [ -e "$device" ]; then
            local perms
            perms=$(ls -la "$device" 2>/dev/null | awk '{print $1, $3, $4}')
            log_success "设备存在: $device ($perms)"
        else
            log_error "设备不存在: $device"
            all_exist=false
        fi
    done
    
    if [ "$all_exist" = true ]; then
        echo "BINDER_DEVICES_EXIST=true" >> "$LOG_FILE"
        return 0
    else
        echo "BINDER_DEVICES_EXIST=false" >> "$LOG_FILE"
        return 1
    fi
}

verify_ashmem_device() {
    log_info "检查 ashmem 设备..."
    
    if [ -e "/dev/ashmem" ]; then
        local perms
        perms=$(ls -la /dev/ashmem 2>/dev/null | awk '{print $1, $3, $4}')
        log_success "ashmem 设备存在: /dev/ashmem ($perms)"
        echo "ASHMEM_DEVICE_EXIST=true" >> "$LOG_FILE"
        return 0
    else
        log_warning "ashmem 设备不存在"
        echo "ASHMEM_DEVICE_EXIST=false" >> "$LOG_FILE"
        return 0
    fi
}

verify_waydroid_installed() {
    log_info "检查 Waydroid 安装..."
    
    if command -v waydroid &> /dev/null; then
        local version
        version=$(waydroid --version 2>/dev/null || echo "unknown")
        log_success "Waydroid 已安装 (版本: $version)"
        echo "WAYDROID_INSTALLED=true" >> "$LOG_FILE"
        echo "WAYDROID_VERSION=$version" >> "$LOG_FILE"
        return 0
    else
        log_error "Waydroid 未安装"
        echo "WAYDROID_INSTALLED=false" >> "$LOG_FILE"
        return 1
    fi
}

verify_waydroid_service() {
    log_info "检查 Waydroid 服务..."
    
    if systemctl is-active --quiet waydroid-container 2>/dev/null; then
        log_success "Waydroid 容器服务运行中"
        echo "WAYDROID_SERVICE_RUNNING=true" >> "$LOG_FILE"
        return 0
    else
        log_warning "Waydroid 容器服务未运行"
        log_info "可以手动启动: sudo systemctl start waydroid-container"
        echo "WAYDROID_SERVICE_RUNNING=false" >> "$LOG_FILE"
        return 0
    fi
}

verify_waydroid_container() {
    log_info "检查 Waydroid 容器状态..."
    
    if command -v waydroid &> /dev/null; then
        local container_status
        container_status=$(waydroid status 2>/dev/null | grep -i "Session" | head -1 || echo "unknown")
        
        if echo "$container_status" | grep -qi "RUNNING"; then
            log_success "Waydroid 容器运行中"
            echo "WAYDROID_CONTAINER_RUNNING=true" >> "$LOG_FILE"
        else
            log_info "Waydroid 容器状态: $container_status"
            log_info "容器尚未启动，可以运行: waydroid session start"
            echo "WAYDROID_CONTAINER_RUNNING=false" >> "$LOG_FILE"
        fi
        
        log_info "Waydroid 状态详情:"
        waydroid status 2>/dev/null | tee -a "$LOG_FILE" || true
    fi
    
    return 0
}

verify_waydroid_images() {
    log_info "检查 Waydroid 镜像..."
    
    local images_dir="/var/lib/waydroid/images"
    
    if [ -d "$images_dir" ]; then
        local image_count
        image_count=$(ls -1 "$images_dir" 2>/dev/null | wc -l)
        
        if [ "$image_count" -gt 0 ]; then
            log_success "找到 $image_count 个镜像文件"
            ls -lh "$images_dir" | tee -a "$LOG_FILE"
            echo "WAYDROID_IMAGES_EXIST=true" >> "$LOG_FILE"
            return 0
        else
            log_warning "镜像目录为空"
            echo "WAYDROID_IMAGES_EXIST=false" >> "$LOG_FILE"
            return 0
        fi
    else
        log_warning "镜像目录不存在: $images_dir"
        echo "WAYDROID_IMAGES_EXIST=false" >> "$LOG_FILE"
        return 0
    fi
}

verify_lxc_config() {
    log_info "检查 LXC 配置..."
    
    local lxc_dir="/var/lib/waydroid/lxc"
    
    if [ -d "$lxc_dir" ]; then
        log_success "LXC 配置目录存在"
        echo "LXC_CONFIG_EXIST=true" >> "$LOG_FILE"
        return 0
    else
        log_warning "LXC 配置目录不存在"
        echo "LXC_CONFIG_EXIST=false" >> "$LOG_FILE"
        return 0
    fi
}

print_summary() {
    local total_checks=10
    local passed_checks=0
    
    echo "" | tee -a "$LOG_FILE"
    echo -e "${BLUE}----------------------------------------${NC}" | tee -a "$LOG_FILE"
    
    verify_kernel_version && ((passed_checks++))
    verify_kernel_modules && ((passed_checks++))
    verify_binder_devices && ((passed_checks++))
    verify_ashmem_device && ((passed_checks++))
    verify_waydroid_installed && ((passed_checks++))
    verify_waydroid_service && ((passed_checks++))
    verify_waydroid_container && ((passed_checks++))
    verify_waydroid_images && ((passed_checks++))
    verify_lxc_config && ((passed_checks++))
    
    echo "" | tee -a "$LOG_FILE"
    
    if [ $passed_checks -eq $total_checks ]; then
        echo -e "${GREEN}状态: 所有检查通过 ✓ ($passed_checks/$total_checks)${NC}" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        log_success "Waydroid 安装验证成功"
        log_info "可以开始使用 Waydroid:"
        log_info "  waydroid session start"
        log_info "  waydroid show-full-ui"
        return 0
    elif [ $passed_checks -ge 7 ]; then
        echo -e "${YELLOW}状态: 基本功能正常 ($passed_checks/$total_checks)${NC}" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        log_warning "部分检查未通过，但核心功能可能正常工作"
        return 0
    else
        echo -e "${RED}状态: 检查未通过 ($passed_checks/$total_checks)${NC}" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        log_error "部分关键组件未正确安装"
        log_info "请检查上述错误信息并修复问题"
        return 1
    fi
}

show_troubleshooting() {
    echo "" | tee -a "$LOG_FILE"
    log_info "故障排除建议:"
    echo "" | tee -a "$LOG_FILE"
    echo "1. 如果 binder 设备不存在:" | tee -a "$LOG_FILE"
    echo "   sudo modprobe binder_linux devices=\"binder,hwbinder,vndbinder\"" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "2. 如果 ashmem 设备不存在:" | tee -a "$LOG_FILE"
    echo "   sudo modprobe ashmem_linux" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "3. 如果 Waydroid 服务未运行:" | tee -a "$LOG_FILE"
    echo "   sudo systemctl start waydroid-container" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "4. 查看 Waydroid 日志:" | tee -a "$LOG_FILE"
    echo "   waydroid log" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "5. 重新初始化 Waydroid:" | tee -a "$LOG_FILE"
    echo "   sudo rm -rf /var/lib/waydroid" | tee -a "$LOG_FILE"
    echo "   sudo waydroid init" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

main() {
    print_header
    
    log_info "开始验证 Waydroid 安装"
    log_info "日志文件: $LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    local exit_code=0
    
    if ! print_summary; then
        exit_code=1
    fi
    
    show_troubleshooting
    
    print_footer
    
    log_info "完整日志已保存到: $LOG_FILE"
    
    exit $exit_code
}

main "$@"
