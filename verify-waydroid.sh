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

# 使用 let 命令进行算术运算，避免 set -e 在结果为0时退出
increment_pass() { let PASS_COUNT++; }
increment_fail() { let FAIL_COUNT++; }
increment_warn() { let WARN_COUNT++; }

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
            found_count=$((found_count+1))
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
