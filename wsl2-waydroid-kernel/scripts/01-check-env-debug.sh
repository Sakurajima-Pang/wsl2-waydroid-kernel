#!/bin/bash

# 调试版本 - 添加详细输出
echo "DEBUG: 脚本开始执行"
echo "DEBUG: Bash版本: $BASH_VERSION"

# 简单的错误处理：打印错误但不退出
# 不使用 set -e 或 trap ERR，避免意外退出

echo "DEBUG: 正在设置变量..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "DEBUG: SCRIPT_DIR=$SCRIPT_DIR"

PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
echo "DEBUG: PROJECT_DIR=$PROJECT_DIR"

LOG_DIR="$PROJECT_DIR/logs"
echo "DEBUG: LOG_DIR=$LOG_DIR"

echo "DEBUG: 创建日志目录..."
mkdir -p "$LOG_DIR"
echo "DEBUG: 日志目录创建完成"

LOG_FILE="$LOG_DIR/01-check-env-$(date +%Y%m%d-%H%M%S).log"
echo "DEBUG: LOG_FILE=$LOG_FILE"

echo "DEBUG: 测试写入日志..."
echo "Test log entry" >> "$LOG_FILE" 2>&1
echo "DEBUG: 日志写入测试完成"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "DEBUG: 颜色变量设置完成"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$LOG_FILE" 2>/dev/null || true
}

echo "DEBUG: log_info 函数定义完成"

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    echo "[✓] $1" >> "$LOG_FILE" 2>/dev/null || true
}

echo "DEBUG: log_success 函数定义完成"

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
    echo "[!] $1" >> "$LOG_FILE" 2>/dev/null || true
}

echo "DEBUG: log_warning 函数定义完成"

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    echo "[✗] $1" >> "$LOG_FILE" 2>/dev/null || true
}

echo "DEBUG: log_error 函数定义完成"

# 辅助函数：输出到屏幕和日志
log_echo() {
    echo "$1"
    echo "$1" >> "$LOG_FILE" 2>/dev/null || true
}

echo "DEBUG: log_echo 函数定义完成"

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   WSL2 Waydroid 环境检查报告 v2.0.0${NC}"
    echo -e "${BLUE}========================================${NC}"
    log_echo ""
}

echo "DEBUG: print_header 函数定义完成"

print_footer() {
    log_echo ""
    echo -e "${BLUE}========================================${NC}"
}

echo "DEBUG: print_footer 函数定义完成"

check_wsl_version() {
    echo "DEBUG: check_wsl_version 开始"
    log_info "检查 WSL 版本..."
    
    # 检查是否在 WSL 环境中（多种方式）
    local is_wsl=false
    
    echo "DEBUG: 检查 wsl.exe..."
    # 方式1: 检查 wsl.exe 命令
    if command -v wsl.exe &> /dev/null; then
        is_wsl=true
        log_info "检测到 wsl.exe 命令"
    fi
    
    echo "DEBUG: 检查 /proc/version..."
    # 方式2: 检查 /proc/version
    if grep -qi "microsoft" /proc/version 2>/dev/null; then
        is_wsl=true
        log_info "通过 /proc/version 检测到 WSL"
    fi
    
    echo "DEBUG: 检查 WSL_INTEROP..."
    # 方式3: 检查 WSL_INTEROP
    if [ -f /run/WSL_INTEROP ]; then
        is_wsl=true
        log_info "通过 WSL_INTEROP 检测到 WSL2"
    fi
    
    echo "DEBUG: is_wsl=$is_wsl"
    if [ "$is_wsl" = false ]; then
        log_error "未检测到 WSL，请确保在 WSL 环境中运行此脚本"
        echo "DEBUG: check_wsl_version 返回 1"
        return 1
    fi
    
    echo "DEBUG: 获取内核版本..."
    local kernel_release
    kernel_release=$(uname -r)
    log_info "内核发布版本: $kernel_release"
    
    echo "DEBUG: 匹配内核版本..."
    # 使用 POSIX 兼容的字符串匹配
    case "$kernel_release" in
        *[Ww][Ss][Ll]2*)
            log_success "WSL 版本: 2"
            echo "WSL_VERSION=2" >> "$LOG_FILE"
            echo "DEBUG: check_wsl_version 返回 0"
            return 0
            ;;
        *[Ww][Ss][Ll]*)
            log_error "WSL 版本: 1 (需要 WSL2)"
            echo "WSL_VERSION=1" >> "$LOG_FILE"
            echo "DEBUG: check_wsl_version 返回 1"
            return 1
            ;;
        *)
            echo "DEBUG: 默认分支..."
            # 检查 /proc/version 作为备选
            if grep -qi "microsoft.*wsl" /proc/version 2>/dev/null; then
                if grep -qi "wsl2" /proc/version 2>/dev/null || [ -f /run/WSL_INTEROP ]; then
                    log_success "WSL 版本: 2 (通过 /proc/version 检测)"
                    echo "WSL_VERSION=2" >> "$LOG_FILE"
                    echo "DEBUG: check_wsl_version 返回 0"
                    return 0
                fi
            fi
            log_error "无法确定 WSL 版本，内核版本: $kernel_release"
            echo "WSL_VERSION=unknown" >> "$LOG_FILE"
            echo "DEBUG: check_wsl_version 返回 1"
            return 1
            ;;
    esac
}

echo "DEBUG: check_wsl_version 函数定义完成"

check_distribution() {
    echo "DEBUG: check_distribution 开始"
    log_info "检查发行版信息..."
    
    if [ -f /etc/os-release ]; then
        local distro_name
        local distro_version
        distro_name=$(grep "^NAME=" /etc/os-release | cut -d'"' -f2)
        distro_version=$(grep "^VERSION_ID=" /etc/os-release | cut -d'"' -f2)
        
        log_success "发行版: $distro_name $distro_version"
        echo "DISTRO=$distro_name" >> "$LOG_FILE"
        echo "VERSION=$distro_version" >> "$LOG_FILE"
        
        case "$distro_name" in
            *Ubuntu*)
                log_success "支持的发行版"
                return 0
                ;;
            *Debian*)
                log_warning "Debian 可能兼容，但未完全测试"
                return 0
                ;;
            *)
                log_warning "未测试的发行版，可能不兼容"
                return 0
                ;;
        esac
    else
        log_error "无法获取发行版信息"
        return 1
    fi
}

echo "DEBUG: check_distribution 函数定义完成"

check_architecture() {
    echo "DEBUG: check_architecture 开始"
    log_info "检查系统架构..."
    
    local arch
    arch=$(uname -m)
    
    case "$arch" in
        x86_64)
            log_success "架构: $arch (支持)"
            echo "ARCH=$arch" >> "$LOG_FILE"
            return 0
            ;;
        aarch64)
            log_success "架构: $arch (支持)"
            echo "ARCH=$arch" >> "$LOG_FILE"
            return 0
            ;;
        *)
            log_error "架构: $arch (不支持)"
            echo "ARCH=$arch" >> "$LOG_FILE"
            return 1
            ;;
    esac
}

echo "DEBUG: check_architecture 函数定义完成"

check_disk_space() {
    echo "DEBUG: check_disk_space 开始"
    log_info "检查磁盘空间..."
    
    local required_gb=20
    local available_kb
    local available_gb
    
    available_kb=$(df -k "$HOME" | tail -1 | awk '{print $4}')
    available_gb=$((available_kb / 1024 / 1024))
    
    echo "DISK_AVAILABLE_GB=$available_gb" >> "$LOG_FILE"
    
    if [ "$available_gb" -ge "$required_gb" ]; then
        log_success "磁盘空间: ${available_gb}GB 可用 (需要 ${required_gb}GB)"
        return 0
    else
        log_error "磁盘空间: ${available_gb}GB 可用 (需要 ${required_gb}GB)"
        return 1
    fi
}

echo "DEBUG: check_disk_space 函数定义完成"

check_network() {
    echo "DEBUG: check_network 开始"
    log_info "检查网络连接..."
    
    local github_accessible=false
    local timeout=10
    
    if curl -s --max-time "$timeout" https://github.com > /dev/null 2>&1; then
        log_success "GitHub 连接: 正常"
        github_accessible=true
    else
        log_warning "GitHub 连接: 超时或无法访问"
        log_info "Clash TUN 模式已配置，如仍无法访问请检查网络"
    fi
    
    echo "GITHUB_ACCESSIBLE=$github_accessible" >> "$LOG_FILE"
    return 0
}

echo "DEBUG: check_network 函数定义完成"

check_kernel_version() {
    echo "DEBUG: check_kernel_version 开始"
    log_info "检查当前内核版本..."
    
    local kernel_version
    kernel_version=$(uname -r)
    
    log_success "内核版本: $kernel_version"
    echo "KERNEL_VERSION=$kernel_version" >> "$LOG_FILE"
    
    return 0
}

echo "DEBUG: check_kernel_version 函数定义完成"

check_memory() {
    echo "DEBUG: check_memory 开始"
    log_info "检查内存..."
    
    local total_mem
    local available_mem
    
    if command -v free &> /dev/null; then
        total_mem=$(free -g | awk '/^Mem:/{print $2}')
        available_mem=$(free -g | awk '/^Mem:/{print $7}')
        
        log_success "总内存: ${total_mem}GB"
        log_success "可用内存: ${available_mem}GB"
        
        if [ "$total_mem" -lt 4 ]; then
            log_warning "内存较少，编译可能需要更长时间"
        fi
        
        echo "MEMORY_TOTAL_GB=$total_mem" >> "$LOG_FILE"
        echo "MEMORY_AVAILABLE_GB=$available_mem" >> "$LOG_FILE"
    else
        log_warning "无法获取内存信息"
    fi
    
    return 0
}

echo "DEBUG: check_memory 函数定义完成"

check_existing_waydroid() {
    echo "DEBUG: check_existing_waydroid 开始"
    log_info "检查现有 Waydroid 安装..."
    
    if command -v waydroid &> /dev/null; then
        local waydroid_version
        waydroid_version=$(waydroid --version 2>/dev/null || echo "unknown")
        log_warning "Waydroid 已安装 (版本: $waydroid_version)"
        echo "WAYDROID_INSTALLED=true" >> "$LOG_FILE"
        echo "WAYDROID_VERSION=$waydroid_version" >> "$LOG_FILE"
    else
        log_success "Waydroid 未安装"
        echo "WAYDROID_INSTALLED=false" >> "$LOG_FILE"
    fi
    
    return 0
}

echo "DEBUG: check_existing_waydroid 函数定义完成"

check_filesystem_case_sensitive() {
    echo "DEBUG: check_filesystem_case_sensitive 开始"
    log_info "检查文件系统大小写敏感性..."
    
    # 检查文件系统类型
    local fs_type
    fs_type=$(df -T "$PROJECT_DIR" 2>/dev/null | awk 'NR==2 {print $2}')
    log_info "项目目录文件系统类型: $fs_type"
    
    local test_dir="$PROJECT_DIR/.fs_test_$(date +%s)"
    mkdir -p "$test_dir"
    
    touch "$test_dir/TestFile" 2>/dev/null
    touch "$test_dir/testfile" 2>/dev/null
    
    local file_count
    file_count=$(ls -1 "$test_dir" 2>/dev/null | wc -l)
    
    rm -rf "$test_dir"
    
    if [ "$file_count" -eq 2 ]; then
        log_success "文件系统支持大小写敏感（推荐）"
        echo "FS_CASE_SENSITIVE=true" >> "$LOG_FILE"
        return 0
    else
        log_warning "文件系统不区分大小写"
        log_info "建议将项目复制到 WSL 虚拟硬盘上:"
        log_info "  cp -r $PROJECT_DIR ~/wsl2-waydroid-kernel"
        log_info "  cd ~/wsl2-waydroid-kernel/scripts"
        log_info "  bash 01-check-env.sh"
        echo "FS_CASE_SENSITIVE=false" >> "$LOG_FILE"
        return 0
    fi
}

echo "DEBUG: check_filesystem_case_sensitive 函数定义完成"

main() {
    echo "DEBUG: main 函数开始"
    print_header
    
    log_info "开始环境检查..."
    log_info "日志文件: $LOG_FILE"
    log_info "检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log_echo ""
    
    local exit_code=0
    local checks_passed=0
    local checks_total=0
    local current_step=0
    local total_steps=9

    show_progress() {
        local step=$1
        local name=$2
        log_info "[$step/$total_steps] 正在检查: $name..."
    }

    echo "DEBUG: 开始第1个检查"
    current_step=$((current_step + 1))
    show_progress $current_step "WSL版本"
    checks_total=$((checks_total + 1))
    if check_wsl_version; then
        checks_passed=$((checks_passed + 1))
    else
        exit_code=1
    fi
    log_echo ""

    echo "DEBUG: 开始第2个检查"
    current_step=$((current_step + 1))
    show_progress $current_step "发行版信息"
    checks_total=$((checks_total + 1))
    if check_distribution; then
        checks_passed=$((checks_passed + 1))
    else
        exit_code=1
    fi
    log_echo ""

    echo "DEBUG: 开始第3个检查"
    current_step=$((current_step + 1))
    show_progress $current_step "系统架构"
    checks_total=$((checks_total + 1))
    if check_architecture; then
        checks_passed=$((checks_passed + 1))
    else
        exit_code=1
    fi
    log_echo ""

    echo "DEBUG: 开始第4个检查"
    current_step=$((current_step + 1))
    show_progress $current_step "磁盘空间"
    checks_total=$((checks_total + 1))
    if check_disk_space; then
        checks_passed=$((checks_passed + 1))
    else
        exit_code=1
    fi
    log_echo ""

    echo "DEBUG: 开始第5个检查"
    current_step=$((current_step + 1))
    show_progress $current_step "网络连接"
    checks_total=$((checks_total + 1))
    if check_network; then
        checks_passed=$((checks_passed + 1))
    else
        exit_code=1
    fi
    log_echo ""

    echo "DEBUG: 开始第6个检查"
    current_step=$((current_step + 1))
    show_progress $current_step "内核版本"
    checks_total=$((checks_total + 1))
    if check_kernel_version; then
        checks_passed=$((checks_passed + 1))
    else
        exit_code=1
    fi
    log_echo ""

    echo "DEBUG: 开始第7个检查"
    current_step=$((current_step + 1))
    show_progress $current_step "内存状态"
    checks_total=$((checks_total + 1))
    if check_memory; then
        checks_passed=$((checks_passed + 1))
    else
        exit_code=1
    fi
    log_echo ""

    echo "DEBUG: 开始第8个检查"
    current_step=$((current_step + 1))
    show_progress $current_step "Waydroid安装状态"
    checks_total=$((checks_total + 1))
    if check_existing_waydroid; then
        checks_passed=$((checks_passed + 1))
    else
        exit_code=1
    fi
    log_echo ""

    echo "DEBUG: 开始第9个检查"
    current_step=$((current_step + 1))
    show_progress $current_step "文件系统大小写敏感"
    checks_total=$((checks_total + 1))
    if check_filesystem_case_sensitive; then
        checks_passed=$((checks_passed + 1))
    else
        exit_code=1
    fi
    log_echo ""
    
    log_echo "----------------------------------------"
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ 状态: 环境检查通过 ($checks_passed/$checks_total)${NC}"
        echo "✓ 状态: 环境检查通过 ($checks_passed/$checks_total)" >> "$LOG_FILE" 2>/dev/null || true
        log_echo ""
        log_info "可以继续执行下一步: bash 02-install-deps.sh"
    else
        echo -e "${YELLOW}⚠ 状态: 环境检查部分通过 ($checks_passed/$checks_total)${NC}"
        echo "⚠ 状态: 环境检查部分通过 ($checks_passed/$checks_total)" >> "$LOG_FILE" 2>/dev/null || true
        log_echo ""
        log_warning "部分检查未通过，但可能仍可继续"
    fi
    
    print_footer
    
    log_info "日志已保存到: $LOG_FILE"
    log_info "检查完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    echo "DEBUG: main 函数结束，exit_code=$exit_code"
    exit $exit_code
}

echo "DEBUG: 所有函数定义完成，准备调用 main"
main "$@"
echo "DEBUG: 脚本结束"
